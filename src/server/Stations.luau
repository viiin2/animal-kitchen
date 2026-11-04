--!strict
-- 스테이션과 플레이어 손. 클라이언트는 ProximityPrompt를 누르기만 하고, 무엇을 할지는 서버가 손과 스테이션을 보고 정한다.
--   E: 꺼내기·집기·내려놓기·쟁반에 담기·손님에게 내기·버리기, 아이스크림 기계 창 열기
--      아이스크림·음료(Config.Dishes의 handheld)는 쟁반 없이 손에 든 채로 바로 낸다.
--   F(길게): 조합대 조합, 토핑 올리기, 소화기로 불 끄기, 개수대 설거지
-- 홀 테이블에서 치운 빈 그릇(dishes)은 쓰레기통에 버리고, 설거지 날(Config.Wash.day)부터는 개수대에서 씻어야 한다.
-- 조합대에는 재료를 세 개까지 올리고, 올린 재료 조합이 디저트(Config.Dishes)와 맞으면 조합된다.
-- 아이스크림 기계(뒷줄 양쪽에 하나씩)는 한 대에 한 명만 쓴다: 창(IceCream.client)에서 고른 그릇·맛·토핑을 서버가 검사해 손에 쥐여 준다.
-- 프롬프트를 켜고 끄는 것은 클라이언트(Prompts)가 한다: 서버는 쓸 수 있는지(속성 On)와 기본 길게 누르는 시간(속성 Hold)만 알려 주고,
-- 클라이언트가 캐릭터가 바라보는 쪽의 가장 가까운 기구 하나만 켠다. 판정은 그대로 서버가 한다.
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local AnimalLooks = require(ReplicatedStorage.Shared.AnimalLooks)
local Items = require(script.Parent.Items)
local Remotes = require(script.Parent.Remotes)
local Store = require(script.Parent.Store)

type Item = Items.Item

type Station = {
	kind: string,
	name: string,
	model: Model,
	base: BasePart,
	slots: { CFrame },
	items: { Item },
	ingredient: string?,
	seat: number?,
	lockId: string?,
	locked: boolean,
	cover: BasePart?,
	tag: SurfaceGui?,
	steam: Smoke?,
	elapsed: number, -- 그릴·냄비·오븐: 올린 뒤 지난 시간
	cookFactor: number, -- 올린 사람의 동물 능력(곰·회색 고양이는 빨리 익힌다)
	onFire: boolean,
	prompt: ProximityPrompt,
	holdPrompt: ProximityPrompt?,
	bar: Frame?,
	barGui: BillboardGui?,
	fire: Fire?,
	user: Player?, -- 아이스크림 기계를 쓰는 사람
	userSince: number,
	lockSign: BillboardGui?, -- 잠겼을 때 위에 뜨는 "🔒 …" 알약(덮개가 없는 기구)
}

export type Modifiers = { cook: number, burn: number, prep: number }

local TICK_SECONDS = 0.1
local GREEN = Color3.fromRGB(110, 196, 120)
local ORANGE = Color3.fromRGB(246, 176, 76)
local RED = Color3.fromRGB(226, 84, 70)
local COOKERS = { grill = true, pot = true, oven = true }
local ICE_TIMEOUT = 60 -- 아이스크림 창을 열어 두고 이만큼 지나면 기계를 놓아 준다
local ICE_REACH = 14 -- 완성할 때 기계에서 이만큼 안에 있어야 한다

local Stations = {}

-- 손님 자리에 쟁반을 내면 부른다. (성공했는지, 알림 문장). Main이 Customers와 Days를 잇는다.
-- 개인 기록(MVP 카드): 아이스크림 만들기·치우기·불 끄기. Main이 Days.stat을 넣는다.
Stations.onStat = function(_player: Player, _key: string, _amount: number) end

-- 돈이 드는 일을 할 때마다 부른다(밤 정산 장부). 키: ing:재료, ice:base·layer·topping, power:기구, extinguisher, wash, trash.
-- 값은 Config.Costs에 있고, Main이 Days.spend를 넣는다.
Stations.onSpend = function(_key: string, _count: number) end

Stations.onServe = function(_player: Player, _seat: number, _dish: Item): (boolean, string)
	return false, "영업 준비 중이에요"
end

local stations: { Station } = {}
local held: { [Player]: Item } = {}
local extinguisherStand: Station? = nil
local washRule = false -- 설거지 날부터: 빈 그릇은 버리지 못하고 개수대에서 씻는다
local mods: Modifiers = { cook = 1, burn = 1, prep = 1 }

local function toast(player: Player, text: string)
	Remotes.toast(player, text)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

-- 화면 아래 "들고 있는 것"이 읽는 값
-- 화면 아래 "들고 있는 것"(Holding, 글)과 친구 머리 위 아이콘(HeldItem, JSON: 모양을 그릴 kind·state·spec·melt·쟁반 여부)
local function setHolding(player: Player)
	local item = held[player]
	player:SetAttribute("Holding", if item then Items.labelText(item) else nil)
	local shown, tray = item, false
	if item and item.kind == "plate" and item.contents then
		shown, tray = item.contents, true
	end
	player:SetAttribute("HeldItem", if shown then HttpService:JSONEncode({ kind = shown.kind, state = shown.state, spec = shown.spec, melt = shown.melt, tray = tray }) else nil)
end

local function give(player: Player, item: Item)
	local root = rootOf(player)
	if not root then
		Items.destroy(item)
		return
	end
	held[player] = item
	Items.hold(item, root)
	setHolding(player)
end

local function takeHeld(player: Player): Item?
	local item = held[player]
	held[player] = nil
	setHolding(player)
	return item
end

local function kindsOf(items: { Item }): { string }
	local kinds = {}
	for _, item in items do
		table.insert(kinds, item.kind)
	end
	return kinds
end

-- 재료 목록이 요리 재료와 정확히 같은지(순서 상관없음)
local function sameSet(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	local left = table.clone(b)
	for _, kind in a do
		local index = table.find(left, kind)
		if not index then
			return false
		end
		table.remove(left, index)
	end
	return true
end

local function matchDish(kinds: { string }): string?
	if #kinds == 0 then
		return nil
	end
	for key, dish in Config.Dishes do
		if not dish.machine and sameSet(kinds, dish.ingredients) then
			return key
		end
	end
	return nil
end

-- 조합대 F 글: 지금 누르면 무엇이 만들어지는지. 모자라면 무엇을 더 올리면 되는지(가장 적게 모자란 디저트).
local function boardAction(items: { Item }): string
	local kinds = kindsOf(items)
	local dish = matchDish(kinds)
	if dish then
		return `{Config.Dishes[dish].name} 만들기`
	end
	local best: string? = nil
	local bestMissing: { string } = {}
	for key, def in Config.Dishes do
		if def.machine then
			continue
		end
		local missing = table.clone(def.ingredients)
		local fits = true
		for _, kind in kinds do
			local index = table.find(missing, kind)
			if not index then
				fits = false
				break
			end
			table.remove(missing, index)
		end
		if fits and (not best or #missing < #bestMissing or (#missing == #bestMissing and key < best)) then
			best, bestMissing = key, missing
		end
	end
	if not best then
		return "이 재료로는 못 만들어요"
	end
	local names = {}
	for _, kind in bestMissing do
		table.insert(names, Config.Ingredients[kind].name)
	end
	return `{table.concat(names, "·")} 더 올리면 {Config.Dishes[best].name}`
end

local function cookingItem(station: Station): Item?
	local item = station.items[1]
	if #station.items == 1 and item and Items.isDish(item) then
		return item
	end
	return nil
end

local function refreshPrompts(station: Station)
	local items = station.items
	local top = items[#items]
	local kind = station.kind
	local action: string
	if kind == "crate" then
		local cost = station.ingredient and Config.Costs.ingredients[station.ingredient]
		action = if cost then `꺼내기 · {cost}코인` else "꺼내기"
	elseif kind == "plates" then
		action = "쟁반 들기"
	elseif kind == "icemachine" then
		action = if station.user then "만드는 중" else "아이스크림 만들기"
	elseif kind == "trash" then
		action = "버리기"
	elseif kind == "sink" then
		action = if top then "꺼내기" else "빈 그릇 넣기"
	elseif kind == "seat" then
		action = "음식 내기"
	elseif station.onFire then
		action = "불났어요!"
	elseif top then
		action = "집기·담기"
	else
		action = "내려놓기"
	end
	station.prompt.ActionText = action
	-- 위에 놓인 것의 이름은 가까이 갔을 때 프롬프트에만 보인다(월드 이름표는 화면을 가려서 없앴다)
	station.prompt.ObjectText = if top and kind ~= "extinguisher" then `{Items.labelText(top)} · {station.name}` else station.name
	station.prompt:SetAttribute("On", not station.locked)
	local holdObject = station.holdPrompt
	if holdObject then
		holdObject.ObjectText = station.prompt.ObjectText
	end

	local holdPrompt = station.holdPrompt
	if holdPrompt then
		local on: boolean
		if station.locked then
			on = false
		elseif kind == "board" then
			on = #items > 0 and Items.isIngredient(items[1])
			if on then
				holdPrompt.ActionText = boardAction(items)
			end
		elseif kind == "sauce" then
			local item = items[1]
			on = item ~= nil and Items.isDish(item) and item.state == "cooked" and Config.Dishes[item.kind].sauce
		elseif kind == "sink" then
			on = #items > 0
		else
			on = station.onFire
		end
		holdPrompt:SetAttribute("On", on)
	end
end

local function changed(station: Station)
	station.elapsed = 0
	refreshPrompts(station)
end

local function setFire(station: Station, on: boolean)
	station.onFire = on
	local fire = station.fire
	if on and not fire then
		local flame = Instance.new("Fire")
		flame.Size = 7
		flame.Heat = 12
		flame.Parent = station.base
		station.fire = flame
		Remotes.toast(nil, "불이야! 소화기를 들고 F를 길게 누르세요")
		Remotes.sfx(nil, "fire")
	elseif not on and fire then
		fire:Destroy()
		station.fire = nil
	end
	refreshPrompts(station)
end

-- 스테이션이 이 물건을 받는지. 안 받으면 이유도 돌려준다.
local function accepts(station: Station, item: Item): (boolean, string)
	local kind = station.kind
	local items = station.items
	if kind == "extinguisher" then
		if item.kind ~= "extinguisher" then
			return false, "소화기 자리예요"
		end
		return #items == 0, "자리가 차 있어요"
	elseif kind == "counter" then
		return #items == 0, "자리가 차 있어요"
	elseif kind == "sink" then
		if item.kind ~= "dishes" then
			return false, "개수대에는 홀에서 치운 빈 그릇만 넣어요"
		end
		return #items < #station.slots, "개수대가 꽉 찼어요. F를 길게 눌러 설거지해요"
	elseif kind == "board" then
		if not Items.isIngredient(item) then
			return false, "조합대에는 재료만 올려요"
		elseif #items > 0 and not Items.isIngredient(items[1]) then
			return false, "조합한 것부터 옮겨요"
		elseif #items >= 3 then
			return false, "조합대가 꽉 찼어요"
		end
		return true, ""
	elseif kind == "sauce" then
		local dish = Config.Dishes[item.kind]
		if #items > 0 then
			return false, "자리가 차 있어요"
		elseif not dish or not dish.sauce then
			return false, "토핑은 딸기 생크림 와플·딸기 케이크에 올려요"
		elseif item.state == "prepped" and dish.cooker then
			return false, `먼저 {Config.Cookers[dish.cooker].name}에서 익혀요`
		elseif item.state ~= "cooked" then
			return false, "이미 토핑을 올렸어요"
		end
		return true, ""
	elseif COOKERS[kind] then
		local cooker = Config.Cookers[kind]
		local dish = Config.Dishes[item.kind]
		if #items > 0 then
			return false, `{cooker.name}이 차 있어요`
		elseif Items.isIngredient(item) then
			return false, "조합대에서 먼저 조합해요 (F 길게)"
		elseif not dish then
			return false, `{cooker.name}에는 조합한 재료를 올려요`
		elseif not dish.cooker then
			return false, "바로 쟁반에 담아요"
		elseif dish.cooker ~= kind then
			return false, `{dish.name}은 {Config.Cookers[dish.cooker].name}에서 익혀요`
		elseif item.state ~= "prepped" then
			return false, "이미 익힌 거예요"
		end
		return true, ""
	end
	return false, ""
end

-- 조리대·조합대·와플 기계·티 냄비·오븐·토핑대·소화기 자리
local function useSurface(player: Player, station: Station)
	if station.onFire then
		toast(player, "불부터 꺼요! 소화기를 들고 F를 길게 누르세요")
		return
	end
	local hand = held[player]
	local items = station.items
	local top = items[#items]

	if not hand then
		if not top then
			toast(player, "비어 있어요")
			return
		end
		table.remove(items)
		give(player, top)
		changed(station)
		return
	end

	if top then
		-- 빈 쟁반으로 떠 담기, 또는 놓여 있는 빈 쟁반에 담기
		if hand.kind == "plate" and Items.addToPlate(hand, top) then
			table.remove(items)
			setHolding(player)
			changed(station)
			return
		end
		if top.kind == "plate" and Items.addToPlate(top, hand) then
			takeHeld(player)
			changed(station)
			return
		end
	end

	local ok, reason = accepts(station, hand)
	if not ok then
		if hand.kind == "plate" and top then
			toast(player, "완성된 디저트만 빈 쟁반에 담을 수 있어요")
		else
			toast(player, reason)
		end
		return
	end
	takeHeld(player)
	table.insert(items, hand)
	Items.putAt(hand, station.slots[#items] or station.slots[1])
	changed(station)
	if COOKERS[station.kind] then
		station.cookFactor = 1 - AnimalLooks.perksFor(player:GetAttribute("AnimalIndex")).cook
		Stations.onSpend("power:" .. station.kind, 1)
	end
end

local function useCrate(player: Player, station: Station)
	local ingredient = station.ingredient
	if held[player] then
		toast(player, "손이 비어야 꺼낼 수 있어요")
	elseif ingredient then
		give(player, Items.new(ingredient, "raw"))
		Stations.onSpend("ing:" .. ingredient, 1)
	end
end

local function usePlates(player: Player)
	local hand = held[player]
	if not hand then
		give(player, Items.new("plate", ""))
	elseif hand.kind == "plate" and not hand.contents then
		takeHeld(player)
		Items.destroy(hand)
	else
		toast(player, "손이 비어야 쟁반을 들 수 있어요")
	end
end

local function useTrash(player: Player)
	local hand = held[player]
	if not hand then
		toast(player, "버릴 게 없어요")
	elseif hand.kind == "plate" then
		if hand.contents then
			Items.clearPlate(hand)
			setHolding(player)
			Stations.onSpend("trash", 1)
		else
			toast(player, "빈 쟁반은 쟁반 자리에 돌려놓아요")
		end
	elseif hand.kind == "extinguisher" then
		toast(player, "소화기는 소화기 자리에 두세요")
	elseif hand.kind == "dishes" and washRule then
		toast(player, "그릇은 버리면 안 돼요! 주방 왼쪽 앞 개수대에서 설거지해요")
	else
		takeHeld(player)
		Items.destroy(hand)
		Remotes.sfx(player, "trash")
		Stations.onSpend("trash", 1)
	end
end

local function useSeat(player: Player, station: Station)
	local hand = held[player]
	local seat = station.seat
	if not seat then
		return
	end
	local dish: Item
	if hand and hand.kind == "plate" then
		local contents = hand.contents
		if not contents then
			toast(player, "빈 쟁반이에요")
			return
		end
		dish = contents
	elseif hand and Items.isDish(hand) then
		if not Config.Dishes[hand.kind].handheld then
			toast(player, "쟁반에 담아야 낼 수 있어요")
			return
		end
		dish = hand
	else
		toast(player, "디저트를 들고 와요")
		return
	end
	local ok, message = Stations.onServe(player, seat, dish)
	if ok and hand then
		takeHeld(player)
		Items.destroy(hand)
	end
	toast(player, message)
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- 화면 움직임(Animals·Kitchen 클라이언트)에 알리는 신호. 판정에는 쓰지 않는다.
--   기구 모델 속성 Cook: "" · "cooking"(익는 중) · "done"(다 익음) · "danger"(곧 탐) · "burnt"
--   기구 모델 속성 DoneAt: 조합·토핑·설거지가 끝난 서버 시각(반짝 효과)
--   플레이어 속성 Working: F 길게 누르는 중이거나 아이스크림 기계를 쓰는 중이면 기구 종류(요리 중 몸 흔들기)
local function setCook(station: Station, value: string)
	if station.model:GetAttribute("Cook") ~= value then
		station.model:SetAttribute("Cook", value)
	end
end

local function sparkle(station: Station)
	station.model:SetAttribute("DoneAt", workspace:GetServerTimeNow())
end

local function releaseMachine(station: Station, closeWindow: boolean)
	local user = station.user
	station.user = nil
	if user and user:GetAttribute("Working") == "icemachine" then
		user:SetAttribute("Working", nil)
	end
	if closeWindow and user and user.Parent then
		Remotes.IceOpen:FireClient(user, false)
	end
	refreshPrompts(station)
end

-- 아이스크림 기계: 손이 비어 있으면 그 사람에게 만들기 창을 연다
local function useMachine(player: Player, station: Station)
	local user = station.user
	if user == player then
		Remotes.IceOpen:FireClient(player, true)
		return
	elseif user and user.Parent then
		toast(player, "친구가 아이스크림을 만들고 있어요")
		return
	end
	if held[player] then
		toast(player, "손이 비어야 아이스크림을 만들 수 있어요")
		return
	end
	-- 기계가 둘이라 다른 기계를 쓰던 중이면 그 기계는 놓아 준다(창은 하나)
	for _, other in stations do
		if other ~= station and other.kind == "icemachine" and other.user == player then
			releaseMachine(other, false)
		end
	end
	station.user = player
	station.userSince = now()
	player:SetAttribute("Working", "icemachine")
	refreshPrompts(station)
	Remotes.IceOpen:FireClient(player, true)
end

-- 창에서 완성(spec) 또는 취소(nil)를 보냈을 때
local function finishMachine(player: Player, value: unknown)
	for _, station in stations do
		if station.kind == "icemachine" and station.user == player then
			releaseMachine(station, false)
			if value == nil then
				return
			end
			local spec = Config.validIce(value)
			local root = rootOf(player)
			if not spec then
				toast(player, "그릇과 맛을 한 층 이상 골라요")
			elseif not root or (root.Position - station.base.Position).Magnitude > ICE_REACH then
				toast(player, "아이스크림 기계 앞에서 완성해요")
			elseif held[player] then
				toast(player, "손이 비어야 받을 수 있어요")
			else
				local melt = 1 + AnimalLooks.perksFor(player:GetAttribute("AnimalIndex")).melt
				give(player, Items.new("icecream", "cooked", { spec = spec, meltSeconds = Config.MeltSeconds * mods.burn * melt }))
				Remotes.sfx(player, "prep")
				toast(player, `{Config.iceName(spec)} 완성! 녹기 전에 내요`)
				Stations.onStat(player, "icecream", 1)
				Stations.onSpend("ice:base", 1)
				Stations.onSpend("ice:layer", #spec.flavors)
				if spec.topping then
					Stations.onSpend("ice:topping", 1)
				end
				Stations.onSpend("power:icemachine", 1)
			end
			return
		end
	end
end

local function use(player: Player, station: Station)
	if station.locked then
		return
	end
	local kind = station.kind
	if kind == "icemachine" then
		useMachine(player, station)
	elseif kind == "crate" then
		useCrate(player, station)
	elseif kind == "plates" then
		usePlates(player)
	elseif kind == "trash" then
		useTrash(player)
	elseif kind == "seat" then
		useSeat(player, station)
	else
		useSurface(player, station)
	end
end

-- 조합대: 올린 재료 조합이 디저트와 맞으면 조합한 디저트로 바꾼다
local function prep(player: Player, station: Station)
	local items = station.items
	for _, item in items do
		if not Items.isIngredient(item) then
			return
		end
	end
	local dish = matchDish(kindsOf(items))
	if not dish then
		toast(player, "이 재료로 만드는 디저트가 없어요. 레시피북을 봐요 (R)")
		return
	end
	for _, item in items do
		Items.destroy(item)
	end
	table.clear(items)
	-- 익힐 곳이 없는 디저트는 조합하자마자 완성이다
	local result = Items.new(dish, if Config.Dishes[dish].cooker then "prepped" else "cooked")
	table.insert(items, result)
	Items.putAt(result, station.slots[1])
	changed(station)
	sparkle(station)
	Remotes.sfx(player, "prep")
end

local function sauce(player: Player, station: Station)
	local item = station.items[1]
	if item and Items.isDish(item) and item.state == "cooked" and Config.Dishes[item.kind].sauce then
		Items.setState(item, "sauced")
		refreshPrompts(station)
		sparkle(station)
		Remotes.sfx(player, "prep")
	end
end

-- 개수대: 맨 위 빈 그릇 하나를 씻는다
local function wash(player: Player, station: Station)
	local item = table.remove(station.items)
	if not item then
		return
	end
	Items.destroy(item)
	changed(station)
	toast(player, "뽀득뽀득! 설거지 끝")
	sparkle(station)
	Stations.onStat(player, "cleaned", 1)
	Stations.onSpend("wash", 1)
	Remotes.sfx(player, "clean")
end

-- 소화기를 든 사람만 불을 끈다. 타던 요리는 없어진다.
local function extinguish(player: Player, station: Station)
	if not station.onFire then
		return
	end
	local hand = held[player]
	if not hand or hand.kind ~= "extinguisher" then
		toast(player, "소화기를 들고 와야 해요")
		return
	end
	for _, item in station.items do
		Items.destroy(item)
	end
	table.clear(station.items)
	setFire(station, false)
	changed(station)
	Remotes.toast(nil, `불을 껐어요! 소화기 충전비 {Config.Costs.extinguisher}코인이 들어요`)
	Stations.onStat(player, "fires", 1)
	Stations.onSpend("extinguisher", 1)
	Remotes.sfx(nil, "clean")
end

local function makeBar(base: BasePart): (Frame, BillboardGui)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Progress"
	-- 크기를 스터드로 정해서 창 크기와 상관없이 기구 크기에 맞게 보인다
	gui.Size = UDim2.new(2.8, 0, 0.36, 0)
	gui.StudsOffset = Vector3.new(0, 2.8, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120
	gui.LightInfluence = 0
	gui.Enabled = false
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(255, 250, 242)
	back.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = back
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BorderSizePixel = 0
	fill.BackgroundColor3 = GREEN
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	fill.Parent = back
	gui.Parent = base
	return fill, gui
end

-- 막대: 익는 중(초록, 차오름) → 다 익음(주황, 탈 때까지 줄어듦) → 탐(빨강)
local function progressOf(station: Station, item: Item): (number, Color3)
	local dish = Config.Dishes[item.kind]
	local cook = dish.cookSeconds * mods.cook * station.cookFactor
	local burn = dish.burnSeconds * mods.burn
	local t = station.elapsed
	if item.state == "prepped" then
		return math.clamp(t / cook, 0, 1), GREEN
	elseif item.state == "cooked" then
		return 1 - math.clamp((t - cook) / burn, 0, 1), ORANGE
	end
	return 1, RED
end

local function tickCookers(dt: number)
	-- 녹는 아이스크림: 모양이 바뀌면 손에 든 사람의 이름도 바꾼다
	if #Items.tickMelt() > 0 then
		for player in held do
			setHolding(player)
		end
	end
	local clock = now()
	for _, station in stations do
		local user = station.user
		if user and (not user.Parent or clock - station.userSince > ICE_TIMEOUT) then
			releaseMachine(station, true)
		end
	end
	for _, station in stations do
		local bar = station.bar
		local barGui = station.barGui
		if not COOKERS[station.kind] or not bar or not barGui then
			continue
		end
		local item = cookingItem(station)
		local steam = station.steam
		if not item or station.onFire then
			setCook(station, "")
			barGui.Enabled = false
			if steam then
				steam.Enabled = false
			end
			continue
		end

		local dish = Config.Dishes[item.kind]
		local cook = dish.cookSeconds * mods.cook * station.cookFactor
		local burnAt = cook + dish.burnSeconds * mods.burn
		station.elapsed += dt
		local t = station.elapsed
		if item.state == "prepped" and t >= cook then
			Items.setState(item, "cooked")
		elseif item.state == "cooked" and t >= burnAt then
			Items.setState(item, "burnt")
		elseif item.state == "burnt" and Config.Cookers[station.kind].fire and t >= burnAt + Config.FireSeconds then
			setFire(station, true)
		end

		local fraction, color = progressOf(station, item)
		setCook(station, if item.state == "prepped" then "cooking" elseif item.state == "burnt" then "burnt" elseif fraction < 0.35 then "danger" else "done")
		bar.Size = UDim2.fromScale(fraction, 1)
		bar.BackgroundColor3 = color
		barGui.Enabled = not station.onFire
		if steam then
			steam.Enabled = item.state ~= "burnt"
		end
	end
end

local function newPrompt(parent: Instance, objectText: string, actionText: string, key: Enum.KeyCode, pad: Enum.KeyCode, hold: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = objectText
	prompt.ActionText = actionText
	prompt.KeyboardKeyCode = key
	prompt.GamepadKeyCode = pad
	prompt.HoldDuration = hold
	prompt:SetAttribute("Hold", hold) -- 클라이언트가 내 동물 능력(강아지·판다)을 곱해 HoldDuration을 정한다
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	-- 기본 프롬프트 UI는 커서 화면을 가린다. 작은 알약 모양은 클라이언트(Prompts)가 그린다
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = parent
	return prompt
end

local function applyHoldDurations()
	for _, station in stations do
		local holdPrompt = station.holdPrompt
		local seconds = if station.kind == "board" then Config.PrepSeconds * mods.prep elseif station.kind == "sauce" then Config.SauceSeconds * mods.prep else nil
		if holdPrompt and seconds then
			holdPrompt.HoldDuration = seconds
			holdPrompt:SetAttribute("Hold", seconds)
		end
	end
end

-- 상점 효과: 조리 시간, 타기·녹기까지 시간, 조합·토핑 시간
function Stations.setModifiers(next: Modifiers)
	mods = next
	applyHoldDurations()
end

-- 잠금 풀기. unlocked에 있는 이름만 열린다. 잠긴 기구는 안내 글 없이 눌러도 반응하지 않고, 재료 상자는 천으로 덮는다.
-- 잠긴 기구 위 알약: 잠긴 줄 모르고 "고장 났나?" 했다(세 번째 티 냄비). 덮개가 있는 재료 상자는 덮개로 충분하다.
local function lockSign(station: Station, hint: string): BillboardGui
	local sign: BillboardGui
	local existing = station.lockSign
	if existing then
		sign = existing
	else
		local gui = Instance.new("BillboardGui")
		gui.Name = "LockSign"
		gui.Size = UDim2.new(4.6, 0, 0.85, 0)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = 90
		gui.LightInfluence = 0
		local pill = Instance.new("TextLabel")
		pill.Name = "Text"
		pill.Size = UDim2.fromScale(1, 1)
		pill.BackgroundColor3 = Color3.fromRGB(255, 250, 244)
		pill.BackgroundTransparency = 0.1
		pill.Font = Enum.Font.GothamBold
		pill.TextScaled = true
		pill.TextColor3 = Color3.fromRGB(150, 130, 118)
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(1, 0)
		round.Parent = pill
		local inset = Instance.new("UIPadding")
		inset.PaddingLeft = UDim.new(0.06, 0)
		inset.PaddingRight = UDim.new(0.06, 0)
		inset.PaddingTop = UDim.new(0.14, 0)
		inset.PaddingBottom = UDim.new(0.14, 0)
		inset.Parent = pill
		pill.Parent = gui
		gui.Parent = station.base
		station.lockSign = gui
		sign = gui
	end
	local label = sign:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = `🔒 {hint}`
	end
	return sign
end

-- hints: 잠금 id마다 언제 열리는지("DAY 3부터", "상점: 티 냄비 추가")
function Stations.applyUnlocks(unlocked: { [string]: boolean }, hints: { [string]: string }?)
	washRule = unlocked["rule:wash"] == true
	for _, station in stations do
		local lockId = station.lockId
		local locked = lockId ~= nil and not unlocked[lockId]
		station.locked = locked
		local cover = station.cover
		if cover then
			cover.Transparency = if locked then 0 else 1
		elseif locked and lockId then
			lockSign(station, (hints and hints[lockId]) or "아직 잠겨 있어요").Enabled = true
		elseif station.lockSign then
			station.lockSign.Enabled = false
		end
		local tag = station.tag
		if tag then
			tag.Enabled = not locked
		end
		station.model:SetAttribute("Locked", locked) -- 튜토리얼 화살표는 열린 기구만 가리킨다
		refreshPrompts(station)
	end
end

-- 주방을 처음 상태로: 손과 스테이션을 비우고 불을 끄고 소화기를 제자리에 둔다
function Stations.reset()
	for player, item in held do
		Items.destroy(item)
		held[player] = nil
		setHolding(player)
	end
	for _, station in stations do
		if station.user then
			releaseMachine(station, true)
		end
		for _, item in station.items do
			Items.destroy(item)
		end
		table.clear(station.items)
		if station.onFire then
			setFire(station, false)
		end
		changed(station)
	end
	local stand = extinguisherStand
	if stand then
		local extinguisher = Items.new("extinguisher", "")
		table.insert(stand.items, extinguisher)
		Items.putAt(extinguisher, stand.slots[1])
		changed(stand)
	end
end

-- 홀 테이블에서 E로 빈 그릇을 집을 때(Tables.onClear). 손이 비어야 집는다.
function Stations.giveDishes(player: Player): boolean
	if held[player] then
		toast(player, "손이 비어야 빈 그릇을 치울 수 있어요")
		return false
	end
	give(player, Items.new("dishes", ""))
	Stations.onStat(player, "cleaned", 1)
	toast(player, if washRule then "빈 그릇은 개수대에서 설거지해요 (주방 왼쪽 앞)" else "빈 그릇은 쓰레기통에 버려요 (홀·주방)")
	return true
end

-- 죽거나 나가면 손에 든 것을 없앤다. 소화기는 제자리로 돌려놓는다. 쓰던 아이스크림 기계도 놓아 준다.
function Stations.drop(player: Player)
	for _, station in stations do
		if station.user == player then
			releaseMachine(station, true)
		end
	end
	local item = takeHeld(player)
	if not item then
		return
	end
	local stand = extinguisherStand
	if item.kind == "extinguisher" and stand and #stand.items == 0 then
		table.insert(stand.items, item)
		Items.putAt(item, stand.slots[1])
		changed(stand)
	else
		Items.destroy(item)
	end
end

function Stations.init(layout: Store.Layout)
	Items.init(layout.items)
	for _, spec in layout.stations do
		local built = spec.built
		local base = built.base
		local point = Instance.new("Attachment")
		point.Name = "PromptPoint"
		point.Parent = base
		local anchor = built.slots[1]
		point.WorldPosition = built.prompt or (if anchor then anchor.Position + Vector3.new(0, 0.5, 0) else base.Position + Vector3.new(0, base.Size.Y / 2 + 0.5, 0))

		local station: Station = {
			kind = spec.kind,
			name = spec.name,
			model = built.model,
			base = base,
			slots = built.slots,
			items = {},
			ingredient = spec.ingredient,
			seat = spec.seat,
			lockId = spec.lockId,
			locked = spec.lockId ~= nil,
			cover = built.cover,
			tag = built.tag,
			steam = built.steam,
			elapsed = 0,
			cookFactor = 1,
			onFire = false,
			prompt = newPrompt(point, spec.name, "", Enum.KeyCode.E, Enum.KeyCode.ButtonX, 0),
			holdPrompt = nil,
			bar = nil,
			barGui = nil,
			fire = nil,
			user = nil,
			userSince = 0,
			lockSign = nil,
		}

		if spec.kind == "board" then
			station.holdPrompt = newPrompt(point, spec.name, "조합하기", Enum.KeyCode.F, Enum.KeyCode.ButtonY, Config.PrepSeconds)
		elseif spec.kind == "sauce" then
			station.holdPrompt = newPrompt(point, spec.name, "토핑 올리기", Enum.KeyCode.F, Enum.KeyCode.ButtonY, Config.SauceSeconds)
		elseif spec.kind == "sink" then
			station.holdPrompt = newPrompt(point, spec.name, "설거지", Enum.KeyCode.F, Enum.KeyCode.ButtonY, Config.Wash.seconds)
		elseif COOKERS[spec.kind] then
			if Config.Cookers[spec.kind].fire then
				station.holdPrompt = newPrompt(point, spec.name, "불 끄기", Enum.KeyCode.F, Enum.KeyCode.ButtonY, Config.ExtinguishSeconds)
			end
			station.bar, station.barGui = makeBar(base)
		end

		CollectionService:AddTag(built.model, "Station")
		station.prompt.Triggered:Connect(function(player: Player)
			use(player, station)
		end)
		local holdPrompt = station.holdPrompt
		if holdPrompt then
			holdPrompt.PromptButtonHoldBegan:Connect(function(player: Player)
				player:SetAttribute("Working", spec.kind)
			end)
			holdPrompt.PromptButtonHoldEnded:Connect(function(player: Player)
				if player:GetAttribute("Working") == spec.kind then
					player:SetAttribute("Working", nil)
				end
			end)
			holdPrompt.Triggered:Connect(function(player: Player)
				if station.locked then
					return
				elseif station.kind == "board" then
					prep(player, station)
				elseif station.kind == "sauce" then
					sauce(player, station)
				elseif station.kind == "sink" then
					wash(player, station)
				else
					extinguish(player, station)
				end
			end)
		end

		if spec.kind == "extinguisher" then
			extinguisherStand = station
		end
		table.insert(stations, station)
	end

	Stations.applyUnlocks({})
	Stations.reset()
	Remotes.IceMake.OnServerEvent:Connect(finishMachine)
	Players.PlayerRemoving:Connect(function(player: Player)
		for _, station in stations do
			if station.user == player then
				releaseMachine(station, false)
			end
		end
	end)

	local pending = 0
	RunService.Heartbeat:Connect(function(dt: number)
		pending += dt
		if pending >= TICK_SECONDS then
			tickCookers(pending)
			pending = 0
		end
	end)
end

return Stations
