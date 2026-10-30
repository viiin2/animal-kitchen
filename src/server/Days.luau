--!strict
-- 하루: 아침(준비) → 카운트다운 → 영업(DAY 1 90초부터, Config.dayParams) → 밤(정산·상점) → 다음 날 아침.
-- 목표 매출을 넘기면 다음 날로, 못 넘기면 같은 날을 다시 한다. 판 만큼 바로 코인(모두의 지갑)이 들어오지만,
-- 목표를 못 넘긴 날은 그날 번 코인을 밤에 반납한다.
-- 아침·밤에는 튜토리얼(연습 손님 두 명, 코인 없음)을 할 수 있고, 끝나면 하던 화면으로 돌아간다.
-- 코인은 상점 업그레이드와 빚 갚기에만 쓴다(동물은 게임패스로 사람마다 연다, Avatars).
-- 가게를 열며 진 빚(Config.Debt)이 있다: 밤마다 이자가 붙고, 얼마나 갚을지는 상점 창에서 직접 고른다.
-- 날마다 새 메뉴가 열리고(Config.Menus의 day) 손님이 더 자주, 덜 기다리며 온다(Config.dayParams).
-- 진행(날·지갑·상점 단계)은 이 서버에서만 이어진다. 저장은 아직 없다.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local Stations = require(script.Parent.Stations)
local Customers = require(script.Parent.Customers)
local Store = require(script.Parent.Store)
local Tables = require(script.Parent.Tables)
local AnimalLooks = require(ReplicatedStorage.Shared.AnimalLooks)

type Today = { sales: number, tips: number, served: number, missed: number, refunded: number }

local TICK_SECONDS = 0.25

local Days = {}

local layout: Store.Layout? = nil
local phase = "morning" -- morning | countdown | open | night | tutorial
local returnPhase = "morning" -- 튜토리얼이 끝나면 돌아갈 화면
local day = 1
local nextDay = 1
local passed = false
local endsAt = 0
local daySeconds = Config.DaySeconds -- 오늘 영업 시간
local target = 0
local wallet = 0
local today: Today = { sales = 0, tips = 0, served = 0, missed = 0, refunded = 0 }
local levels: { [string]: number } = {}
local debt = Config.Debt.start
local debtNight = { interest = 0 } -- 지난밤 붙은 이자

-- 그날 개인 기록과 마감 MVP 카드(부문마다 가장 잘한 사람, 기록이 있는 부문만)
type MvpCard = { icon: string, title: string, name: string, detail: string, animal: number }
local stats: { [Player]: { [string]: number } } = {}
local mvp: { MvpCard } = {}
local MVP_KINDS = {
	{ key = "served", icon = "🍰", title = "서빙왕", detail = function(n: number): string
		return `{n}번 냈어요`
	end },
	{ key = "coins", icon = "💰", title = "코인왕", detail = function(n: number): string
		return `+{n} 코인`
	end },
	{ key = "icecream", icon = "🍦", title = "아이스크림 장인", detail = function(n: number): string
		return `{n}개 만들었어요`
	end },
	{ key = "cleaned", icon = "🧽", title = "청소왕", detail = function(n: number): string
		return `{n}번 치웠어요`
	end },
	{ key = "fires", icon = "🧯", title = "불 끈 영웅", detail = function(n: number): string
		return `{n}번 껐어요`
	end },
}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function playerCount(): number
	return math.max(1, #Players:GetPlayers())
end

local function level(id: string): number
	return levels[id] or 0
end

-- 아침·밤 화면이 보여 줄 날(밤에는 내일)
local function upcomingDay(): number
	local shown = if phase == "tutorial" then returnPhase else phase
	return if shown == "night" then nextDay else day
end

local function menusUntil(d: number): { Config.MenuDef }
	local list = {}
	for _, menu in Config.Menus do
		if menu.day <= d then
			table.insert(list, menu)
		end
	end
	return list
end

-- 잠금 이름별로 처음 열리는 날
local function unlockDays(): { [string]: number }
	local first: { [string]: number } = {}
	local function mark(id: string, d: number)
		first[id] = math.min(first[id] or math.huge, d)
	end
	mark("rule:wash", Config.Wash.day)
	for _, menu in Config.Menus do
		local dish = Config.Dishes[menu.dish]
		for _, ingredient in dish.ingredients do
			mark("ing:" .. ingredient, menu.day)
		end
		local cooker = dish.cooker
		if cooker then
			mark("menu:" .. cooker, menu.day)
		end
		if dish.sauce then
			mark("menu:sauce", menu.day)
		end
	end
	return first
end

-- 상점(폭신 운동화)과 그 사람 동물 능력(토끼·판다 등)을 더한 이동 속도
local function walkSpeed(player: Player): number
	local perk = AnimalLooks.perksFor(player:GetAttribute("AnimalIndex")).speed
	return Config.WalkSpeed * (1 + 0.1 * level("move") + perk)
end

local function applyEffects()
	local d = upcomingDay()
	local unlocked: { [string]: boolean } = {}
	for id, openDay in unlockDays() do
		unlocked[id] = openDay <= d
	end
	for _, upgrade in Config.Upgrades do
		unlocked["up:" .. upgrade.id] = level(upgrade.id) > 0
	end
	Stations.applyUnlocks(unlocked)
	Stations.setModifiers({
		cook = 1 - 0.12 * level("cook"),
		burn = 1 + 0.4 * level("burn"),
		prep = 1 - 0.25 * level("prep"),
	})
	for _, player in Players:GetPlayers() do
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = walkSpeed(player)
		end
	end
end

Days.walkSpeed = walkSpeed

local function snapshot()
	local d = upcomingDay()
	local menus = {}
	for _, menu in menusUntil(d) do
		table.insert(menus, {
			dish = menu.dish,
			name = Config.Dishes[menu.dish].name,
			steps = Config.steps(menu.dish),
			price = menu.price,
			isNew = menu.day == d and d > 1,
		})
	end
	local shop = {}
	for _, upgrade in Config.Upgrades do
		local lv = level(upgrade.id)
		table.insert(shop, {
			id = upgrade.id,
			name = upgrade.name,
			desc = upgrade.desc,
			level = lv,
			max = #upgrade.costs,
			cost = upgrade.costs[lv + 1],
		})
	end
	-- 그날 새로 생기는 규칙(아침 창·밤 정산의 '내일'에 보인다)
	local rules = {}
	if d == Config.DineIn.day then
		table.insert(rules, "손님이 홀 테이블에 앉아 먹고 가요. 다 먹은 테이블은 카운터 옆 통로로 나가 E로 빈 그릇을 치우고 쓰레기통(홀·주방)에 버려야 다음 손님이 앉아요.")
	end
	if d == Config.Groups.day then
		table.insert(rules, "단체 손님이 와요! 한 자리에서 2개를 주문하고, 다 내면 단체 보너스를 줘요.")
	end
	if d == Config.Villains.day then
		table.insert(rules, "골치 아픈 손님이 와요! 급한 손님(팁 2배), 기다리다 주문을 바꾸는 변덕쟁이, 받은 걸 떨어뜨리는 덜렁이(다시 내면 팁 1.5배).")
	end
	if d == Config.Wash.day then
		table.insert(rules, "이제 빈 그릇은 버리지 말고 주방 왼쪽 앞 개수대에 넣고 F를 길게 눌러 설거지해요.")
	end
	return {
		phase = phase,
		day = day,
		upcomingDay = d,
		endsAt = endsAt,
		daySeconds = if phase == "open" or phase == "countdown" then daySeconds else Config.dayParams(d, playerCount()).seconds,
		target = if phase == "morning" or phase == "night" then Config.dayParams(d, playerCount()).target else target,
		wallet = wallet,
		today = today,
		passed = passed,
		menus = menus,
		shop = shop,
		rules = rules,
		debt = debt,
		mvp = if phase == "night" then mvp else {},
		debtNight = debtNight,
	}
end

local function broadcast()
	Remotes.State:FireAllClients(snapshot())
end

function Days.sendTo(player: Player)
	Remotes.State:FireClient(player, snapshot())
end

local function setDoors(open: boolean)
	local current = layout
	if current then
		Store.setDoors(current, open)
	end
end

-- 남은 손님이 문을 지나 나간 뒤에 닫는다(그 사이 다시 열었으면 그대로 둔다)
local function closeDoorsLater()
	task.delay(4, function()
		if phase ~= "open" and phase ~= "tutorial" then
			setDoors(false)
		end
	end)
end

local function setTime(progress: number, night: boolean)
	local current = layout
	if current then
		Store.setTime(current, progress, night)
	end
end

function Days.start()
	if phase ~= "morning" and phase ~= "night" then
		return
	end
	if phase == "night" then
		day = nextDay
	end
	phase = "countdown"
	passed = false
	today = { sales = 0, tips = 0, served = 0, missed = 0, refunded = 0 }
	stats = {}
	Stations.reset()
	Tables.reset()
	applyEffects()
	target = Config.dayParams(day, playerCount()).target
	endsAt = now() + Config.CountdownSeconds
	daySeconds = Config.dayParams(day, playerCount()).seconds
	setTime(0, false)
	broadcast()
end

local function open()
	local params = Config.dayParams(day, playerCount())
	target = params.target
	phase = "open"
	daySeconds = params.seconds
	endsAt = now() + daySeconds
	setDoors(true)
	Customers.start({
		patience = params.patience * (1 + 0.2 * level("chair")),
		interval = params.interval,
		maxCustomers = params.maxCustomers,
		tipRate = Config.TipRate * (1 + 0.2 * level("tip")),
		menus = menusUntil(day),
		newestDay = day,
		dineChance = Config.dineChance(day),
	})
	broadcast()
end

-- 밤 빚 정산: 남은 빚에 이자만 붙는다(갚는 것은 플레이어가 상점 창에서)
local function settleDebt()
	local interest = if debt > 0 then math.ceil(debt * Config.Debt.interest) else 0
	debt += interest
	debtNight = { interest = interest }
end

local function pickMvp()
	mvp = {}
	for _, kind in MVP_KINDS do
		local best: Player? = nil
		local bestValue = 0
		for player, values in stats do
			local value = values[kind.key] or 0
			if value > bestValue and player.Parent then
				best, bestValue = player, value
			end
		end
		if best then
			local animal = best:GetAttribute("AnimalIndex")
			table.insert(mvp, {
				icon = kind.icon,
				title = kind.title,
				name = best.DisplayName,
				detail = kind.detail(bestValue),
				animal = if typeof(animal) == "number" then animal else 1,
			})
		end
	end
end

local function finish()
	Customers.stop()
	pickMvp()
	closeDoorsLater()
	passed = today.sales >= target
	if not passed then
		-- 실패한 날 번 코인은 반납(낮에는 상점이 닫혀 있어서 지갑에는 그날 번 코인이 그대로 있다)
		today.refunded = math.min(today.sales, wallet)
		wallet -= today.refunded
	end
	settleDebt()
	nextDay = if passed then day + 1 else day
	phase = "night"
	Stations.reset()
	Tables.reset()
	applyEffects()
	setTime(1, true)
	Remotes.toast(nil, if passed then `DAY {day} 목표 달성!` else `DAY {day} 목표 미달, 오늘 번 {today.refunded} 코인은 반납했어요`)
	broadcast()
end

-- 손님에게 요리를 냈을 때(Main이 Customers.serveAt 성공 뒤 부른다). 판 만큼 바로 코인이 들어온다. 튜토리얼은 세지 않는다.
function Days.earn(price: number, tip: number)
	if phase ~= "open" then
		return
	end
	today.sales += price + tip
	today.tips += tip
	today.served += 1
	wallet += price + tip
	broadcast()
end

function Days.missed()
	today.missed += 1
	Remotes.toast(nil, "손님이 기다리다 돌아갔어요")
	broadcast()
end

-- 상점: 아침이나 밤에만, 모두가 같이 쓰는 지갑으로 산다
function Days.buy(player: Player, id: unknown)
	if typeof(id) ~= "string" then
		return
	end
	if phase ~= "morning" and phase ~= "night" then
		Remotes.toast(player, "상점은 영업 전·후에 열려요")
		return
	end
	for _, upgrade in Config.Upgrades do
		if upgrade.id == id then
			local lv = level(id)
			local cost = upgrade.costs[lv + 1]
			if not cost then
				Remotes.toast(player, "이미 최고 단계예요")
			elseif wallet < cost then
				Remotes.toast(player, `코인이 {cost - wallet} 모자라요`)
			else
				wallet -= cost
				levels[id] = lv + 1
				applyEffects()
				Remotes.toast(nil, `{player.DisplayName}님이 '{upgrade.name}'을(를) 샀어요`)
				Remotes.sfx(nil, "buy")
				broadcast()
			end
			return
		end
	end
end

-- 관리자 DAY 패스(테스트용): 영업 중이면 목표를 채운 걸로 치고 바로 마감,
-- 아침·밤이면 바로 다음 DAY 아침으로(밤에는 그날을 통과한 것으로 친다). 코인은 늘지 않는다.
function Days.adminPass()
	if phase == "open" or phase == "countdown" then
		today.sales = math.max(today.sales, target)
		finish()
		return
	elseif phase ~= "morning" and phase ~= "night" then
		return
	end
	day = if phase == "night" then math.max(nextDay, day + 1) else day + 1
	nextDay = day
	phase = "morning"
	passed = false
	today = { sales = 0, tips = 0, served = 0, missed = 0, refunded = 0 }
	Stations.reset()
	Tables.reset()
	applyEffects()
	setTime(0, false)
	Remotes.toast(nil, `관리자: DAY {day}로 넘어갔어요`)
	broadcast()
end

-- 관리자 영업 그만하기(테스트용): 영업·튜토리얼 도중에 정산 없이 같은 DAY 아침으로 돌아간다.
-- 그날 번 코인은 없던 걸로 하고, 손님은 돌려보낸다.
function Days.adminStop()
	if phase == "tutorial" then
		Days.endTutorial(false)
		return
	elseif phase ~= "open" and phase ~= "countdown" then
		return
	end
	Customers.stop()
	wallet -= math.min(wallet, today.sales)
	today = { sales = 0, tips = 0, served = 0, missed = 0, refunded = 0 }
	stats = {}
	phase = "morning"
	passed = false
	Stations.reset()
	Tables.reset()
	applyEffects()
	setTime(0, false)
	closeDoorsLater()
	Remotes.toast(nil, `관리자: 영업을 그만두고 DAY {day} 아침으로 돌아왔어요`)
	broadcast()
end

-- 개인 기록 더하기(영업 중에만): served·coins(Main), icecream·cleaned·fires(Stations)
function Days.stat(player: Player, key: string, amount: number)
	if phase ~= "open" then
		return
	end
	local mine = stats[player] or {}
	mine[key] = (mine[key] or 0) + amount
	stats[player] = mine
end

-- 빚 더 갚기: 아침·밤에만. amount는 코인 수 또는 "all"
function Days.payDebt(player: Player, amount: unknown)
	if phase ~= "morning" and phase ~= "night" then
		Remotes.toast(player, "빚은 영업 전·후에 갚아요")
		return
	end
	local want = if amount == "all" then debt elseif typeof(amount) == "number" and amount > 0 then math.floor(amount) else 0
	local pay = math.min(want, debt, wallet)
	if debt <= 0 then
		Remotes.toast(player, "갚을 빚이 없어요")
	elseif pay <= 0 then
		Remotes.toast(player, "코인이 없어요")
	else
		wallet -= pay
		debt -= pay
		Remotes.toast(nil, if debt <= 0 then "빚을 다 갚았어요! 이제 가게가 온전히 우리 거예요" else `{player.DisplayName}님이 빚 {pay}을(를) 갚았어요 (남은 빚 {debt})`)
		Remotes.sfx(nil, if debt <= 0 then "win" else "buy")
		broadcast()
	end
end

-- 튜토리얼: 아침·밤에만 시작한다. 정해진 손님 두 명(Config.Tutorial)을 받으면 끝난다.
function Days.startTutorial()
	if phase ~= "morning" and phase ~= "night" then
		return
	end
	returnPhase = phase
	phase = "tutorial"
	setDoors(true)
	Stations.reset()
	Tables.reset()
	setTime(0.2, false)
	Customers.start({
		patience = 900,
		interval = 2,
		maxCustomers = 1,
		tipRate = 0,
		menus = menusUntil(1),
		newestDay = 1,
		dineChance = 0,
		script = Config.Tutorial,
	})
	broadcast()
end

function Days.endTutorial(finished: boolean)
	if phase ~= "tutorial" then
		return
	end
	Customers.stop()
	Stations.reset()
	local back = returnPhase
	phase = back
	closeDoorsLater()
	setTime(if back == "night" then 1 else 0, back == "night")
	Remotes.toast(nil, if finished then "튜토리얼 끝! 이제 영업을 시작해 봐요" else "튜토리얼을 건너뛰었어요")
	broadcast()
end

local function tick()
	local t = now()
	if phase == "countdown" and t >= endsAt then
		open()
	elseif phase == "open" then
		setTime(1 - (endsAt - t) / daySeconds, false)
		if t >= endsAt then
			finish()
		end
	end
end

function Days.init(store: Store.Layout)
	layout = store
	Customers.onScriptDone = function()
		Days.endTutorial(true)
	end
	applyEffects()
	setTime(0, false)
	local pending = 0
	RunService.Heartbeat:Connect(function(dt: number)
		pending += dt
		if pending >= TICK_SECONDS then
			pending = 0
			tick()
		end
	end)
	-- 인원이 바뀌면 다음 날 목표가 바뀐다
	Players.PlayerAdded:Connect(function()
		broadcast()
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(broadcast)
	end)
end

return Days
