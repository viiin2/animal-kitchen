--!strict
-- 손님: 왼쪽 문으로 들어와 빈 자리 앞에 서서 주문하고, 받거나 기다리다 지치면 오른쪽 문으로 나간다.
-- 주문은 손님 모델 속성으로 내보내고(Orders JSON·Order·Group·OrderedAt·ExpiresAt·Mood), 말풍선은 클라이언트가 그린다.
-- 아이스크림 주문은 그릇·맛·토핑까지 정해서 말풍선에 그대로 그리고, 낼 때 똑같은지 확인한다.
-- 단체 손님(Config.Groups)은 일행 1~2명과 함께 와서 한 자리에서 2~3개를 주문한다. 하나씩 낼 때마다 값을 받고, 다 내면 보너스.
-- 골치 아픈 손님(Config.Villains): 급한 손님·변덕쟁이(주문을 한 번 바꿈)·덜렁이(받은 걸 떨어뜨려 한 번 더 주문). 말풍선에 속성 Note로 알린다.
-- DineIn.day부터는 받은 손님 일부가 홀 테이블(Tables)에 앉아 먹고 간다(단체 손님은 들고 간다).
-- 빈 테이블이 없으면 카운터 자리를 차지한 채 기다린다. 튜토리얼은 정해진 주문(Params.script)을 가운데 자리에 한 명씩 보낸다.
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(ReplicatedStorage.Shared.Build)
local Critters = require(script.Parent.Critters)
local Remotes = require(script.Parent.Remotes)
local Store = require(script.Parent.Store)
local Tables = require(script.Parent.Tables)

export type ScriptStep = { dish: string, spec: Config.IceSpec? }

export type Params = {
	patience: number,
	interval: number,
	maxCustomers: number,
	tipRate: number,
	menus: { Config.MenuDef },
	newestDay: number, -- 오늘. 새로 나온 메뉴는 더 자주 주문하고, 아이스크림·단체 주문도 날마다 늘어난다
	dineChance: number, -- 받은 뒤 홀에서 먹고 갈 확률(Config.dineChance)
	script: { ScriptStep }?, -- 튜토리얼: 이 주문들만 차례로
}

export type Served = { kind: string, state: string, melt: number, spec: Config.IceSpec? }

type Order = { dish: string, spec: Config.IceSpec?, price: number, done: boolean }

type Customer = {
	model: Model,
	extras: { Model }, -- 단체 손님의 일행(주문은 앞사람이 한다)
	seat: Store.Seat,
	holdsSeat: boolean, -- 카운터 자리를 차지하고 있는지
	orders: { Order },
	group: boolean,
	phase: string, -- arriving | waiting | eating | waitTable | toTable | dining | leaving
	path: { Vector3 },
	walkStart: number,
	patience: number, -- 이 손님이 기다리는 시간(단체는 더 길다)
	expiresAt: number,
	deadline: number, -- eating·waitTable·dining이 끝나는 때
	dine: boolean,
	tableIndex: number?,
	sitAt: CFrame?,
	served: Served?,
	villain: string?, -- rush | changer | dropper
	changeAt: number, -- 변덕쟁이가 주문을 바꾸는 때
	changed: boolean,
	dropped: boolean, -- 덜렁이가 이미 한 번 떨어뜨렸는지
}

local WALK_SPEED = 9
local VILLAINS = { "rush", "changer", "dropper" }
local EAT_SECONDS = 1.6 -- 받고 하트를 띄우는 시간
local SIT_HEIGHT = 1.15 -- 의자에 앉을 때 올리는 높이
local TUTORIAL_SEAT = 3
-- 일행이 서는 곳(앞사람 기준 양옆 조금 뒤)
local COMPANION_OFFSETS = { CFrame.new(-2.1, 0, 1.4), CFrame.new(2.1, 0, 1.4) }

local Customers = {}

-- 기다리다 나간 손님 수를 센다. Main이 Days에 잇는다.
Customers.onMissed = function() end
-- 튜토리얼 주문을 다 받았을 때
Customers.onScriptDone = function() end

local layout: Store.Layout? = nil
local params: Params? = nil
local active = false
local list: { Customer } = {}
local occupied: { [number]: boolean } = {}
local nextSpawnAt = 0
local scriptSpawned = 0
local scriptServed = 0
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

-- 경로 위 위치와 바라볼 방향. 끝까지 갔으면 true.
local function along(path: { Vector3 }, distance: number): (Vector3, Vector3, boolean)
	local remaining = distance
	for i = 2, #path do
		local a, b = path[i - 1], path[i]
		local length = (b - a).Magnitude
		if remaining <= length and length > 0 then
			return a:Lerp(b, remaining / length), (b - a).Unit, false
		end
		remaining -= length
	end
	local last = path[#path]
	local before = path[#path - 1] or last
	local direction = if (last - before).Magnitude > 0 then (last - before).Unit else Vector3.new(0, 0, 1)
	return last, direction, true
end

-- 앞사람과 일행을 함께 옮긴다
local function place(customer: Customer, cframe: CFrame)
	customer.model:PivotTo(cframe)
	for i, extra in customer.extras do
		extra:PivotTo(cframe * COMPANION_OFFSETS[i])
	end
end

local function orderName(order: Order): string
	local spec = order.spec
	return if spec then Config.iceName(spec) else Config.Dishes[order.dish].name
end

local function pickMenu(p: Params): Config.MenuDef
	local pool: { Config.MenuDef } = {}
	for _, menu in p.menus do
		table.insert(pool, menu)
		if menu.day == p.newestDay and p.newestDay > 1 then
			table.insert(pool, menu)
		end
	end
	return pool[rng:NextInteger(1, #pool)]
end

local function randomIce(day: number): Config.IceSpec
	local ice = Config.IceCream
	local maxLayers, toppingChance = Config.iceRules(day)
	local flavors = {}
	for _ = 1, rng:NextInteger(1, maxLayers) do
		table.insert(flavors, ice.flavors[rng:NextInteger(1, #ice.flavors)].id)
	end
	return {
		base = ice.bases[rng:NextInteger(1, #ice.bases)].id,
		flavors = flavors,
		topping = if rng:NextNumber() < toppingChance then ice.toppings[rng:NextInteger(1, #ice.toppings)].id else nil,
	}
end

local function freeSeat(p: Params): Store.Seat?
	local current = layout
	if not current then
		return nil
	end
	local fixed = current.seats[TUTORIAL_SEAT]
	if p.script and fixed then
		return if occupied[fixed.index] then nil else fixed
	end
	local free = {}
	for _, seat in current.seats do
		if not occupied[seat.index] then
			table.insert(free, seat)
		end
	end
	if #free == 0 then
		return nil
	end
	return free[rng:NextInteger(1, #free)]
end

local function releaseSeat(customer: Customer)
	if customer.holdsSeat then
		customer.holdsSeat = false
		occupied[customer.seat.index] = false
	end
end

-- 지금 있는 곳에서 손님 길로 나가 오른쪽 문으로 간다
local function leave(customer: Customer, mood: string)
	local current = layout
	if not current then
		return
	end
	releaseSeat(customer)
	local index = customer.tableIndex
	if index and customer.phase == "toTable" then
		Tables.release(index)
	end
	customer.phase = "leaving"
	customer.model:SetAttribute("Mood", mood)
	local here = customer.model:GetPivot().Position
	local from = Vector3.new(here.X, 0, here.Z)
	customer.path = { from, Vector3.new(from.X, 0, current.lane.z), current.lane.exit }
	customer.walkStart = now()
end

local function makeOrder(p: Params, menu: Config.MenuDef): Order
	local spec = if Config.Dishes[menu.dish].machine then randomIce(p.newestDay) else nil
	return { dish = menu.dish, spec = spec, price = if spec then Config.icePrice(spec) else menu.price, done = false }
end

-- 다음 손님의 주문: 튜토리얼이면 정해진 차례대로, 아니면 오늘 메뉴에서 고른다(가끔 단체로 2~3개)
local function nextOrders(p: Params): { Order }?
	local steps = p.script
	if steps then
		local step = steps[scriptSpawned + 1]
		if not step then
			return nil
		end
		scriptSpawned += 1
		local spec = step.spec
		return { { dish = step.dish, spec = if spec then { base = spec.base, flavors = table.clone(spec.flavors), topping = spec.topping } else nil, price = 0, done = false } }
	end
	local count = 1
	if rng:NextNumber() < Config.groupChance(p.newestDay) then
		count = if p.newestDay > Config.Groups.day then rng:NextInteger(2, 3) else 2
	end
	local orders = {}
	for _ = 1, count do
		table.insert(orders, makeOrder(p, pickMenu(p)))
	end
	return orders
end

local function spawn(p: Params)
	local current = layout
	local seat = freeSeat(p)
	if not current or not seat then
		return
	end
	local orders = nextOrders(p)
	if not orders then
		return
	end
	occupied[seat.index] = true
	local group = #orders > 1
	local model = Critters.customer()
	model:SetAttribute("Seat", seat.index)
	model.Parent = current.customers
	local extras = {}
	for _ = 2, #orders do
		local extra = Critters.customer()
		extra:SetAttribute("Companion", true) -- 말풍선 없음
		extra.Parent = current.customers
		table.insert(extras, extra)
	end
	local villain: string? = nil
	if not group and not p.script and p.newestDay >= Config.Villains.day and rng:NextNumber() < Config.Villains.chance then
		villain = VILLAINS[rng:NextInteger(1, #VILLAINS)]
	end
	local patience = p.patience * (if group then Config.Groups.patience elseif villain == "rush" then Config.Villains.rushPatience else 1)
	local stand = seat.stand.Position
	local customer: Customer = {
		model = model,
		extras = extras,
		seat = seat,
		holdsSeat = true,
		orders = orders,
		group = group,
		phase = "arriving",
		path = { current.lane.entry, Vector3.new(stand.X, 0, current.lane.z), stand },
		walkStart = now(),
		patience = patience,
		expiresAt = 0,
		deadline = 0,
		dine = false,
		tableIndex = nil,
		sitAt = nil,
		served = nil,
		villain = villain,
		changeAt = 0,
		changed = false,
		dropped = false,
	}
	place(customer, CFrame.new(current.lane.entry))
	table.insert(list, customer)
end

-- 말풍선이 읽는 주문 목록(낸 것은 done)
local function publish(customer: Customer)
	local entries = {}
	local names = {}
	for _, order in customer.orders do
		table.insert(entries, { food = order.dish, state = Config.servedState(order.dish), spec = order.spec, done = order.done })
		if not order.done then
			table.insert(names, orderName(order))
		end
	end
	customer.model:SetAttribute("Orders", HttpService:JSONEncode(entries))
	customer.model:SetAttribute("Order", table.concat(names, " · "))
end

local function order(customer: Customer)
	local t = now()
	customer.phase = "waiting"
	customer.expiresAt = t + customer.patience
	place(customer, customer.seat.stand)
	local model = customer.model
	publish(customer)
	model:SetAttribute("Group", customer.group)
	model:SetAttribute("Note", if customer.villain == "rush" then "급해요!" else nil)
	customer.changeAt = t + customer.patience * Config.Villains.changeAt
	model:SetAttribute("OrderedAt", t)
	model:SetAttribute("ExpiresAt", customer.expiresAt)
	model:SetAttribute("Mood", "waiting")
end

-- 홀 테이블로: 빈 테이블이 있으면 걸어가고, 없으면 카운터에서 기다린다
local function goToTable(customer: Customer)
	local current = layout
	if not current then
		return
	end
	local index, at = Tables.reserve()
	if index and at then
		releaseSeat(customer)
		customer.tableIndex = index
		customer.sitAt = at
		customer.phase = "toTable"
		customer.model:SetAttribute("Mood", "walking")
		local from = customer.seat.stand.Position
		local to = at.Position
		customer.path = { from, Vector3.new(from.X, 0, current.lane.z), Vector3.new(to.X, 0, current.lane.z), to }
		customer.walkStart = now()
	elseif customer.phase ~= "waitTable" then
		customer.phase = "waitTable"
		customer.deadline = now() + Config.DineIn.waitSeconds
		customer.model:SetAttribute("Mood", "table")
		Remotes.toast(nil, "앉을 테이블이 없어요! 홀 테이블을 치워 주세요 (F 길게)")
	end
end

local function sit(customer: Customer)
	local at = customer.sitAt
	local index = customer.tableIndex
	if not at or not index then
		leave(customer, "happy")
		return
	end
	customer.phase = "dining"
	customer.deadline = now() + Config.DineIn.eatSeconds
	place(customer, at * CFrame.new(0, SIT_HEIGHT, 0))
	customer.model:SetAttribute("Mood", "dining")
	local served = customer.served
	if served then
		Tables.serve(index, served.kind, served.state, served.spec)
	end
end

-- 변덕쟁이: 아직 안 낸 주문을 다른 메뉴로 한 번 바꾼다
local function changeOrder(customer: Customer, p: Params)
	customer.changed = true
	local current = customer.orders[1]
	if not current or current.done then
		return
	end
	local others = {}
	for _, menu in p.menus do
		if menu.dish ~= current.dish then
			table.insert(others, menu)
		end
	end
	local menu = if #others > 0 then others[rng:NextInteger(1, #others)] else p.menus[1]
	customer.orders[1] = makeOrder(p, menu)
	publish(customer)
	customer.model:SetAttribute("Note", "주문 바꿈!")
	Remotes.toast(nil, `변덕쟁이 손님이 {orderName(customer.orders[1])}(으)로 주문을 바꿨어요!`)
	Remotes.sfx(nil, "order")
end

-- 덜렁이가 떨어뜨린 디저트(잠깐 바닥에 남는다)
local function splat(customer: Customer, kind: string, spec: Config.IceSpec?)
	local current = layout
	if not current then
		return
	end
	local color = Color3.fromRGB(250, 176, 198)
	if spec and spec.flavors[1] then
		local flavor = Config.findIceOption(Config.IceCream.flavors, spec.flavors[1])
		color = if flavor then flavor.color else color
	elseif kind == "milk_tea" or kind == "bubble_tea" then
		color = Color3.fromRGB(214, 172, 132)
	end
	local foot = customer.model:GetPivot().Position
	local puddle = Build.disc(current.customers, 1.8, 0.06, CFrame.new(foot + Vector3.new(0.6, 0.04, 1.2)), color)
	Build.ball(current.customers, 0.5, CFrame.new(foot + Vector3.new(0.9, 0.15, 1.4)), color)
	Debris:AddItem(puddle, 6)
end

local function remove(customer: Customer)
	customer.model:Destroy()
	for _, extra in customer.extras do
		extra:Destroy()
	end
end

local function tick()
	local t = now()
	for i = #list, 1, -1 do
		local customer = list[i]
		local phase = customer.phase
		if phase == "arriving" or phase == "leaving" or phase == "toTable" then
			local distance = (t - customer.walkStart) * WALK_SPEED
			local position, direction, arrived = along(customer.path, distance)
			local hop = math.abs(math.sin(distance * 1.4)) * 0.35
			place(customer, CFrame.lookAt(position + Vector3.new(0, hop, 0), position + Vector3.new(direction.X, hop, direction.Z)))
			if arrived and phase == "leaving" then
				remove(customer)
				table.remove(list, i)
			elseif arrived and phase == "toTable" then
				sit(customer)
			elseif arrived then
				if active and params then
					order(customer)
				else
					leave(customer, "bye")
				end
			end
		elseif phase == "waiting" and t >= customer.expiresAt then
			leave(customer, "angry")
			Customers.onMissed()
		elseif phase == "waiting" and customer.villain == "changer" and not customer.changed and t >= customer.changeAt and params then
			changeOrder(customer, params)
		elseif phase == "eating" and t >= customer.deadline then
			if customer.dine and active then
				goToTable(customer)
			else
				leave(customer, "happy")
			end
		elseif phase == "waitTable" then
			if t >= customer.deadline then
				leave(customer, "angry")
			else
				goToTable(customer)
			end
		elseif phase == "dining" and t >= customer.deadline then
			local index = customer.tableIndex
			if index then
				Tables.leave(index)
			end
			customer.tableIndex = nil
			leave(customer, "happy")
		end
	end

	local p = params
	if active and p and t >= nextSpawnAt then
		local present = 0
		for _, customer in list do
			if customer.holdsSeat then
				present += 1
			end
		end
		if present < p.maxCustomers then
			spawn(p)
		end
		nextSpawnAt = t + p.interval * rng:NextNumber(0.8, 1.2)
	end
end

function Customers.init(store: Store.Layout)
	layout = store
	RunService.Heartbeat:Connect(tick)
end

function Customers.start(p: Params)
	params = p
	active = true
	scriptSpawned = 0
	scriptServed = 0
	nextSpawnAt = now() + 1.5
end

-- 영업이 끝나면 남은 손님은 그냥 돌아간다(놓친 손님으로 세지 않는다)
function Customers.stop()
	active = false
	for _, customer in list do
		if customer.phase ~= "leaving" then
			leave(customer, "bye")
		end
	end
end

-- 낸 디저트가 이 주문에 맞는지. 맞지 않으면 이유.
local function check(order: Order, served: Served): (boolean, string?)
	local spec = order.spec
	if spec then
		if served.melt >= 2 then
			return false, "다 녹아 버렸어요. 새로 만들어요"
		elseif not served.spec or not Config.sameIce(served.spec, spec) then
			return false, `주문과 달라요: {orderName(order)}`
		end
		return true, nil
	end
	local cooker = Config.Dishes[order.dish].cooker
	if served.state == "prepped" and cooker then
		return false, `먼저 {Config.Cookers[cooker].name}에서 익혀요`
	elseif served.state == "burnt" then
		return false, "탄 건 낼 수 없어요. 버리고 다시 만들어요"
	elseif served.state ~= Config.servedState(order.dish) then
		return false, "토핑을 올려야 해요 (토핑대 F 길게)"
	end
	return true, nil
end

-- 손님 자리에 낸 디저트를 확인한다. (성공했는지, 알림 문장, 가격, 팁). tipBonus는 낸 사람의 동물 능력(0.25 = 팁 +25%).
-- 단체 손님은 남은 주문 중 맞는 하나를 채우고, 마지막 하나를 낼 때 단체 보너스를 팁에 더한다.
function Customers.serveAt(seatIndex: number, served: Served, tipBonus: number?): (boolean, string, number, number)
	local p = params
	if not active or not p then
		return false, "영업 중에만 낼 수 있어요", 0, 0
	end
	local customer: Customer? = nil
	for _, c in list do
		if c.seat.index == seatIndex and c.phase == "waiting" then
			customer = c
			break
		end
	end
	if not customer then
		return false, "이 자리에는 주문한 손님이 없어요", 0, 0
	end
	local match: Order? = nil
	local reason: string? = nil
	local pending = {}
	for _, o in customer.orders do
		if not o.done then
			table.insert(pending, orderName(o))
			if o.dish == served.kind and not match then
				local ok, why = check(o, served)
				if ok then
					match = o
				else
					reason = reason or why
				end
			end
		end
	end
	if not match then
		return false, reason or `{table.concat(pending, ", ")}을(를) 주문했어요`, 0, 0
	end

	match.done = true
	local left = math.clamp((customer.expiresAt - now()) / customer.patience, 0, 1)
	local price = match.price
	local tipScale = if customer.villain == "rush" then Config.Villains.rushTip elseif customer.dropped then Config.Villains.sorryTip else 1
	local tip = math.floor(price * p.tipRate * (1 + (tipBonus or 0)) * left * tipScale + 0.5)
	local done, total, sum = 0, #customer.orders, 0
	for _, o in customer.orders do
		sum += o.price
		if o.done then
			done += 1
		end
	end
	publish(customer)
	if done < total then
		return true, `{orderName(match)} 완성! 단체 손님 {done}/{total} +{price + tip} 코인`, price, tip
	end

	-- 덜렁이: 처음 받은 걸 떨어뜨리고 같은 걸 한 번 더 주문한다(이번 건 돈을 안 낸다)
	if customer.villain == "dropper" and not customer.dropped and not p.script then
		customer.dropped = true
		for _, o in customer.orders do
			o.done = false
		end
		customer.expiresAt = now() + customer.patience * 0.8
		customer.model:SetAttribute("OrderedAt", now())
		customer.model:SetAttribute("ExpiresAt", customer.expiresAt)
		customer.model:SetAttribute("Note", "떨어뜨렸어요!")
		publish(customer)
		splat(customer, served.kind, served.spec)
		Remotes.sfx(nil, "angry")
		return true, "앗, 덜렁이 손님이 떨어뜨렸어요! 한 번 더 만들어 주면 팁을 더 줘요", 0, 0
	end

	customer.phase = "eating"
	customer.deadline = now() + EAT_SECONDS
	customer.served = served
	customer.dine = not customer.group and p.dineChance > 0 and rng:NextNumber() < p.dineChance
	customer.model:SetAttribute("Mood", "happy")
	if p.script then
		scriptServed += 1
		if scriptServed >= #p.script then
			task.delay(2, function()
				Customers.onScriptDone()
			end)
		end
		return true, `{orderName(match)} 완성! 잘했어요`, 0, 0
	end
	if customer.group then
		local bonus = math.floor(sum * Config.Groups.bonus + 0.5)
		return true, `단체 주문 완성! +{price + tip + bonus} 코인 (단체 보너스 {bonus})`, price, tip + bonus
	end
	return true, `{orderName(match)} 완성! +{price + tip} 코인 (팁 {tip})`, price, tip
end

return Customers
