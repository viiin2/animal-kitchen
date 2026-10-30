--!strict
-- 게임 밸런스 값과 이름. 숫자는 여기서만 고친다.
-- 동물 디저트 카페. 흐름: 재료 상자 → 조합대(F 길게) → (와플 기계·티 냄비·오븐) → (토핑대 F 길게) → 쟁반 → 손님 앞 자리

export type IngredientDef = { name: string }

-- 아이스크림 기계 창에서 만드는 아이스크림: 그릇, 아래부터 쌓은 맛(1~3층), 토핑(없을 수 있음)
export type IceSpec = { base: string, flavors: { string }, topping: string? }
export type IceOption = { id: string, name: string, color: Color3 }

export type DishDef = {
	name: string,
	ingredients: { string }, -- 조합대에 올리는 재료(순서 상관없음)
	cooker: string?, -- Cookers 키. 없으면 조합하자마자 완성
	cookSeconds: number, -- 올린 뒤 익을 때까지
	burnSeconds: number, -- 익은 뒤 탈(넘칠) 때까지
	sauce: boolean, -- 익힌 뒤 토핑대에서 토핑을 올려야 완성
	machine: boolean?, -- 조합대가 아니라 전용 기계 창에서 만든다(아이스크림)
	handheld: boolean?, -- 쟁반 없이 손에 든 채로 바로 손님에게 낸다(아이스크림·음료)
}

export type MenuDef = { dish: string, price: number, day: number }

export type CookerDef = { name: string, verb: string, fire: boolean }

export type UpgradeDef = { id: string, name: string, desc: string, icon: string, costs: { number } }

export type DayParams = {
	patience: number, -- 손님이 기다리는 시간(초)
	interval: number, -- 손님이 오는 간격(초)
	maxCustomers: number, -- 동시에 카운터에 있는 손님 수
	target: number, -- 목표 매출
	seconds: number, -- 영업 시간
}

local Config = {}

Config.DaySeconds = 150 -- 하루 영업 최대 길이. DAY 1은 90초에서 하루 +20초씩(Config.dayParams)
Config.CountdownSeconds = 3
Config.WalkSpeed = 13.5 -- 플레이 테스트에서 20은 너무 빨랐다(1/3 줄임)
Config.PrepSeconds = 1.5 -- 조합대(F 길게)
Config.SauceSeconds = 1.2 -- 토핑 올리기(F 길게)
Config.ExtinguishSeconds = 1 -- 소화기로 불 끄기(F 길게)
Config.FireSeconds = 5 -- 탄 뒤 불이 날 때까지(와플 기계·오븐)
Config.MeltSeconds = 45 -- 아이스크림을 꺼낸 뒤 다 녹을 때까지. 60%가 지나면 흘러내리기 시작한다
Config.TipRate = 0.5 -- 인내심이 가득할 때 가격의 50%까지 팁

Config.Ingredients = {
	tea = { name = "찻잎" },
	milk = { name = "우유" },
	pearl = { name = "타피오카 펄" },
	batter = { name = "반죽" },
	strawberry = { name = "딸기" },
} :: { [string]: IngredientDef }

-- 재료 상자를 놓는 순서(뒷벽, 아이스크림 기계 오른쪽부터)
Config.CrateOrder = { "tea", "milk", "pearl", "batter", "strawberry" }

-- 아이스크림 기계: 창에서 그릇·맛·토핑을 고르면 완성된 아이스크림이 손에 나온다
Config.IceCream = {
	bases = {
		{ id = "cone", name = "콘", color = Color3.fromRGB(226, 176, 110) },
		{ id = "cup", name = "컵", color = Color3.fromRGB(190, 224, 246) },
	} :: { IceOption },
	flavors = {
		{ id = "strawberry", name = "딸기", color = Color3.fromRGB(250, 176, 198) },
		{ id = "vanilla", name = "바닐라", color = Color3.fromRGB(252, 244, 222) },
		{ id = "chocolate", name = "초코", color = Color3.fromRGB(150, 100, 74) },
		{ id = "mint", name = "민트", color = Color3.fromRGB(170, 230, 208) },
	} :: { IceOption },
	toppings = {
		{ id = "sprinkles", name = "스프링클", color = Color3.fromRGB(246, 120, 160) },
		{ id = "berry", name = "딸기", color = Color3.fromRGB(236, 64, 84) },
		{ id = "cherry", name = "체리", color = Color3.fromRGB(214, 30, 52) },
		{ id = "chip", name = "초코칩", color = Color3.fromRGB(150, 100, 74) }, -- 초코 맛과 같은 갈색
	} :: { IceOption },
	maxLayers = 3,
	basePrice = 10,
	layerPrice = 3, -- 한 층 더할 때마다
	toppingPrice = 3,
}

Config.Cookers = {
	grill = { name = "와플 기계", verb = "굽기", fire = true },
	pot = { name = "티 냄비", verb = "끓이기", fire = false },
	oven = { name = "오븐", verb = "굽기", fire = true },
} :: { [string]: CookerDef }

Config.Dishes = {
	icecream = { name = "아이스크림", ingredients = {}, cookSeconds = 0, burnSeconds = 0, sauce = false, machine = true, handheld = true },
	milk_tea = { name = "밀크티", ingredients = { "tea", "milk" }, cooker = "pot", cookSeconds = 7, burnSeconds = 9, sauce = false, handheld = true },
	bubble_tea = { name = "버블티", ingredients = { "tea", "milk", "pearl" }, cooker = "pot", cookSeconds = 9, burnSeconds = 8, sauce = false, handheld = true },
	waffle = { name = "와플", ingredients = { "batter" }, cooker = "grill", cookSeconds = 7, burnSeconds = 9, sauce = false },
	strawberry_waffle = { name = "딸기 생크림 와플", ingredients = { "batter", "strawberry" }, cooker = "grill", cookSeconds = 8, burnSeconds = 9, sauce = true },
	strawberry_cake = { name = "딸기 케이크", ingredients = { "batter", "strawberry", "milk" }, cooker = "oven", cookSeconds = 11, burnSeconds = 11, sauce = true },
} :: { [string]: DishDef }

-- 날마다 새 메뉴가 하나씩 늘어난다. 늦게 나오는 메뉴일수록 단계가 많고 비싸다.
Config.Menus = {
	{ dish = "icecream", price = 10, day = 1 }, -- 실제 가격은 주문한 아이스크림에 따라(Config.icePrice)
	{ dish = "milk_tea", price = 10, day = 1 },
	{ dish = "bubble_tea", price = 18, day = 2 },
	{ dish = "waffle", price = 20, day = 3 },
	{ dish = "strawberry_waffle", price = 26, day = 4 },
	{ dish = "strawberry_cake", price = 32, day = 5 },
} :: { MenuDef }

-- 밤 상점. costs의 길이가 최대 단계 수다.
Config.Upgrades = {
	{ id = "cook", name = "화력 조절", desc = "와플 기계·냄비·오븐 시간 -12%", icon = "🔥", costs = { 80, 160, 260 } },
	{ id = "prep", name = "척척 조합", desc = "조합·토핑 시간 -25%", icon = "🥄", costs = { 60, 140 } },
	{ id = "move", name = "폭신 운동화", desc = "모두의 이동 속도 +10%", icon = "👟", costs = { 70, 150 } },
	{ id = "burn", name = "꼼꼼 타이머", desc = "타기·녹기까지 시간 +40%", icon = "⏰", costs = { 120 } },
	{ id = "chair", name = "푹신한 쿠션 의자", desc = "손님 인내심 +20%", icon = "🪑", costs = { 90, 180 } },
	{ id = "tip", name = "반짝 메뉴판", desc = "팁 +20%", icon = "✨", costs = { 80, 160 } },
	{ id = "grill3", name = "와플 기계 추가", desc = "세 번째 와플 기계를 연다", icon = "🧇", costs = { 150 } },
	{ id = "pot3", name = "티 냄비 추가", desc = "세 번째 티 냄비를 연다", icon = "🧋", costs = { 150 } },
	{ id = "board3", name = "조합대 추가", desc = "세 번째 조합대를 연다", icon = "🍓", costs = { 100 } },
} :: { UpgradeDef }

-- 날이 갈수록 영업이 조금 길어지고, 손님이 조금씩 자주 오고 덜 기다린다. 인원이 많으면 손님과 목표가 늘어난다.
-- 플레이 테스트: 한 판(특히 DAY 1)이 길고, DAY 1 목표가 높고, DAY 3부터 갑자기 어려웠다.
-- 그래서 DAY 1은 90초, 목표는 "1초에 벌 코인"(DAY 1 0.35, 하루 +0.05)×영업 시간으로 정한다.
function Config.dayParams(day: number, players: number): DayParams
	local extra = math.clamp(players, 1, 4) - 1
	local seconds = math.min(Config.DaySeconds, 90 + (day - 1) * 20)
	local rate = math.min(0.75, 0.3 + 0.05 * day)
	return {
		patience = math.max(40, 80 - (day - 1) * 4),
		interval = math.max(8, 13 - (day - 1) * 0.6) / (1 + 0.4 * extra),
		maxCustomers = math.min(5, 2 + day // 2),
		target = math.floor(rate * seconds * (1 + 0.6 * extra) / 5 + 0.5) * 5,
		seconds = seconds,
	}
end

-- 빚: 가게를 열며 진 빚. 밤마다 남은 빚에 이자가 붙고, 얼마나 갚을지는 아침·밤 상점 창에서 직접 고른다
-- (일찍 갚을수록 이자가 줄어든다. 자동 상환은 플레이 테스트에서 빼 달라고 했다).
Config.Debt = {
	start = 400,
	interest = 0.02, -- 밤마다 남은 빚의 2%
}

-- 팀 콤보: 다른 친구가 이 시간 안에 이어서 내면 콤보가 오르고, 콤보마다 코인을 더 준다
Config.Combo = { seconds = 10, bonus = 3 }

-- 단체 손님: 이 날부터 가끔 일행과 함께 와서 한 자리에서 2~3개를 한꺼번에 주문한다(다음 날부터 3개도).
-- 하나씩 낼 때마다 그 디저트 값을 받고, 다 내면 주문 합계의 bonus만큼 더 받는다. 기다리는 시간은 patience배.
Config.Groups = { day = 3, patience = 1.8, bonus = 0.3 }

function Config.groupChance(day: number): number
	if day < Config.Groups.day then
		return 0
	end
	return math.min(0.3, 0.15 + 0.05 * (day - Config.Groups.day))
end

-- 골치 아픈 손님(빌런): 이 날부터 가끔(혼자 온 손님 중 chance) 온다.
--   rush 급한 손님: 기다리는 시간 rushPatience배, 팁 rushTip배
--   changer 변덕쟁이: 기다리는 시간의 changeAt만큼 지나면 주문을 한 번 바꾼다
--   dropper 덜렁이: 받은 디저트를 떨어뜨려 한 번 더 주문한다(첫 번째는 돈을 안 내고, 두 번째에 팁 sorryTip배)
Config.Villains = { day = 5, chance = 0.2, rushPatience = 0.55, rushTip = 2, changeAt = 0.35, sorryTip = 1.5 }

-- 효과음: 로블록스에 기본으로 들어 있는 소리(rbxasset://sounds/…)를 높낮이만 바꿔 쓴다.
-- 더 좋은 소리로 바꾸려면 Creator Store(오디오)에서 고른 소리의 id를 "rbxassetid://숫자"로 넣으면 된다.
export type SoundDef = { id: string, speed: number, volume: number }
local PING = "rbxasset://sounds/electronicpingshort.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"
local SWOOSH = "rbxasset://sounds/swoosh.wav"
local VICTORY = "rbxasset://sounds/victory.wav"
Config.Sounds = {
	coin = { id = PING, speed = 1.3, volume = 0.45 }, -- 띠롱(두 번째 음은 coinHigh)
	coinHigh = { id = PING, speed = 1.75, volume = 0.45 },
	pick = { id = CLICK, speed = 1.25, volume = 0.35 },
	drop = { id = CLICK, speed = 0.85, volume = 0.35 },
	order = { id = PING, speed = 0.9, volume = 0.35 }, -- 손님이 주문할 때 딩동
	angry = { id = PING, speed = 0.5, volume = 0.45 },
	prep = { id = SWOOSH, speed = 1.35, volume = 0.45 }, -- 조합·토핑 완성
	fire = { id = PING, speed = 2.2, volume = 0.55 },
	clean = { id = SWOOSH, speed = 1, volume = 0.45 }, -- 불 끄기·테이블 치우기
	trash = { id = SWOOSH, speed = 0.7, volume = 0.45 },
	tick = { id = CLICK, speed = 1.6, volume = 0.5 }, -- 카운트다운
	start = { id = PING, speed = 1.1, volume = 0.55 },
	win = { id = VICTORY, speed = 1, volume = 0.45 },
	lose = { id = PING, speed = 0.45, volume = 0.5 },
	buy = { id = PING, speed = 1.5, volume = 0.45 },
	click = { id = CLICK, speed = 1, volume = 0.25 },
} :: { [string]: SoundDef }

-- 배경 음악: 이 게임용으로 직접 만든 멜로디(Music.client)를 기본 '띵' 소리 높낮이로 연주한다(저작권 걱정 없음).
-- trackId에 Creator Store의 로블록스 라이선스 음악 id("rbxassetid://숫자")를 넣으면 그 곡을 대신 반복한다.
Config.Music = { trackId = "", sample = PING, volume = 0.6, bpm = 112 }

-- 홀 테이블: 이 날부터 손님 일부가 디저트를 받아 홀 테이블에 앉아 먹고 간다.
-- 먹고 간 테이블에는 빈 그릇이 남고, 플레이어가 F를 길게 눌러 치워야 다음 손님이 앉는다.
-- 빈 테이블이 없으면 손님은 카운터 자리에서 기다리고(그동안 그 자리에 새 손님이 못 온다), 너무 오래면 그냥 간다.
Config.DineIn = {
	day = 4, -- 와플이 나오는 DAY 3과 겹치지 않게 하루 뒤로
	eatSeconds = 9,
	waitSeconds = 20,
}

-- 설거지: 이 날부터 홀 테이블에서 치운 빈 그릇은 버릴 수 없고, 개수대에 넣고 F를 길게 눌러 씻어야 한다
Config.Wash = { day = 6, seconds = 1.6 }

-- 그날 손님이 홀에서 먹고 갈 확률
function Config.dineChance(day: number): number
	if day < Config.DineIn.day then
		return 0
	end
	return math.min(0.6, 0.3 + 0.1 * (day - Config.DineIn.day))
end

-- 손님에게 낼 수 있는 상태: 소스가 필요한 메뉴는 sauced, 아니면 cooked
function Config.servedState(dish: string): string
	return if Config.Dishes[dish].sauce then "sauced" else "cooked"
end

-- 날마다 아이스크림 주문이 조금씩 복잡해진다: 최대 층 수, 토핑을 올릴 확률
function Config.iceRules(day: number): (number, number)
	if day <= 1 then
		return 1, 0
	elseif day == 2 then
		return 2, 0.2
	elseif day == 3 then
		return 2, 0.35
	elseif day == 4 then
		return 3, 0.45
	end
	return 3, 0.6
end

local function findOption(list: { IceOption }, id: string): IceOption?
	for _, option in list do
		if option.id == id then
			return option
		end
	end
	return nil
end
Config.findIceOption = findOption

function Config.icePrice(spec: IceSpec): number
	local ice = Config.IceCream
	return ice.basePrice + ice.layerPrice * (#spec.flavors - 1) + (if spec.topping then ice.toppingPrice else 0)
end

-- "딸기·초코 콘 + 스프링클"
function Config.iceName(spec: IceSpec): string
	local ice = Config.IceCream
	local names = {}
	for _, flavor in spec.flavors do
		local option = findOption(ice.flavors, flavor)
		table.insert(names, if option then option.name else flavor)
	end
	local base = findOption(ice.bases, spec.base)
	local text = `{table.concat(names, "·")} {if base then base.name else ""}`
	local topping = spec.topping and findOption(ice.toppings, spec.topping)
	return if topping then `{text} + {topping.name}` else text
end

-- 클라이언트가 보낸 값을 검사해 올바른 아이스크림만 돌려준다
function Config.validIce(value: unknown): IceSpec?
	if typeof(value) ~= "table" then
		return nil
	end
	local raw = value :: { [any]: any }
	local ice = Config.IceCream
	local base, flavors, topping = raw.base, raw.flavors, raw.topping
	if typeof(base) ~= "string" or not findOption(ice.bases, base) or typeof(flavors) ~= "table" then
		return nil
	end
	local clean = {}
	for i = 1, ice.maxLayers + 1 do
		local flavor = (flavors :: { any })[i]
		if flavor == nil then
			break
		elseif typeof(flavor) ~= "string" or not findOption(ice.flavors, flavor) then
			return nil
		end
		table.insert(clean, flavor)
	end
	if #clean < 1 or #clean > ice.maxLayers then
		return nil
	end
	if topping ~= nil and (typeof(topping) ~= "string" or not findOption(ice.toppings, topping)) then
		return nil
	end
	return { base = base, flavors = clean, topping = topping }
end

-- 같은 아이스크림인지: 그릇·토핑이 같고 맛은 순서 상관없이 같으면 된다
function Config.sameIce(a: IceSpec, b: IceSpec): boolean
	if a.base ~= b.base or a.topping ~= b.topping or #a.flavors ~= #b.flavors then
		return false
	end
	local left = table.clone(b.flavors)
	for _, flavor in a.flavors do
		local index = table.find(left, flavor)
		if not index then
			return false
		end
		table.remove(left, index)
	end
	return true
end

-- 레시피북에 쓰는 한 줄 순서
function Config.steps(dish: string): string
	local def = Config.Dishes[dish]
	if def.machine then
		return "아이스크림 기계(E) → 그릇·맛·토핑 고르기 → 손님"
	end
	local names = {}
	for _, ingredient in def.ingredients do
		table.insert(names, Config.Ingredients[ingredient].name)
	end
	local parts = { table.concat(names, " + "), "조합대(F)" }
	local cooker = def.cooker
	if cooker then
		table.insert(parts, Config.Cookers[cooker].name)
	end
	if def.sauce then
		table.insert(parts, "토핑대(F)")
	end
	if not def.handheld then
		table.insert(parts, "쟁반")
	end
	table.insert(parts, "손님")
	return table.concat(parts, " → ")
end

-- 카메라 시점: C 키나 화면 오른쪽 카메라 버튼으로 차례로 바꾼다(LocalPlayer 속성 CameraMode). 첫 번째가 기본.
Config.CameraModes = {
	{ id = "follow", name = "따라가기" }, -- 내 캐릭터를 위에서 따라간다(마우스 휠로 확대·축소)
	{ id = "behind", name = "뒤에서 보기" }, -- 내 캐릭터 뒤통수 위에서 캐릭터가 보는 쪽을 본다(W 앞, S 뒤, A·D 돌기)
	{ id = "fixed", name = "전체 보기" }, -- 주방과 카운터가 다 보이는 고정 시점
}

Config.Camera = {
	position = Vector3.new(0, 46, 37), -- 주방 뒤 위에서 카운터 쪽 손님을 내려다본다(전체 보기)
	focus = Vector3.new(0, 0, -1.5),
	halfWidth = 26, -- 이 폭(스터드)이 화면 가로에 다 들어오게 시야각을 맞춘다
	minFieldOfView = 40,
}

-- 튜토리얼 손님: 차례대로 한 명씩, 기다리는 시간 제한 없이 온다
Config.Tutorial = {
	{ dish = "icecream", spec = { base = "cone", flavors = { "vanilla" } } :: IceSpec },
	{ dish = "milk_tea" },
} :: { { dish: string, spec: IceSpec? } }

-- 관리자(테스트용 DAY 패스 버튼): Studio에서는 모두, 실제 서버에서는 게임 주인과 여기 적은 UserId만
Config.Admins = {} :: { number }

Config.QuickChat = { "도와줘!", "내가 할게!", "불 났어!", "좋아!" }
Config.QuickChatCooldown = 1

Config.Remotes = {
	State = "KitchenState",
	Toast = "KitchenToast",
	Ready = "ClientReady",
	Start = "StartDay",
	Buy = "BuyUpgrade",
	IceOpen = "IceCreamOpen",
	IceMake = "IceCreamMake",
	Animal = "PickAnimal",
	Tutorial = "Tutorial",
	Unstuck = "Unstuck",
	PayDebt = "PayDebt",
	Earned = "CoinsEarned",
	Sfx = "Sfx",
	Admin = "AdminAction",
	Chat = "QuickChat",
}

return Config
