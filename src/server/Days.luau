--!strict
-- 하루: 아침(준비) → 카운트다운 → 영업(DAY 1 90초부터, Config.dayParams) → 밤(정산·상점) → 다음 날 카운트다운.
-- 목표 매출은 없다. 낮에 판 돈은 가게 금고에 모이고, 영업 중 쓴 운영비(Config.Costs)는 세어 두었다가
-- 밤 정산에서 월세·빚 상환금(Config.Debt)과 함께 금고에서 낸다. 남은 순수익은 인원수로 똑같이 나눠 각자 지갑에 넣는다.
-- 적자면 각자 지갑에서 1/n씩 메우고, 그래도 모자라면 연체(모자란 돈 + 연체료가 빚으로)다.
-- Config.Debt.strikes번 연체하면 파산해서 DAY 1 아침부터 다시 한다(지갑·빚·상점 단계도 처음으로).
-- 밤 정산 화면은 Config.NightSeconds 동안 보이고, 모두 준비를 누르거나 시간이 지나면 다음 날 영업이 시작된다.
-- 아침·밤에는 튜토리얼(연습 손님 두 명, 코인 없음)을 할 수 있고, 끝나면 하던 화면으로 돌아간다.
-- 개인 지갑은 상점 업그레이드(산 사람 돈만 빠지고 효과는 모두에게)와 빚 더 갚기에 쓴다. 동물은 게임패스로 연다(Avatars).
-- 날마다 새 메뉴가 열리고(Config.Menus의 day) 손님이 더 자주, 덜 기다리며 온다(Config.dayParams).
-- 진행(날·지갑·상점 단계)은 이 서버에서만 이어진다. 사람마다 최고 기록(며칠까지 버텼는지)만 저장한다(Records).
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
local Records = require(script.Parent.Records)

type Today = { sales: number, tips: number, served: number, missed: number }
-- 밤 장부 한 줄: 묶음 이름, 금액, 자세히("찻잎 5×1 · 우유 6×1")
type Line = { name: string, amount: number, detail: string }
-- 운영비 한 항목: 쓴 횟수 × 값. fixed는 횟수 없이 값만 보인다(기본 전기세)
type Entry = { name: string, count: number, unit: number, fixed: boolean? }
-- 사람마다 나눠 받은(+)·메운(−) 돈과 남은 지갑
type Share = { userId: number, name: string, change: number, wallet: number }
type Report = {
	income: { Line },
	expenses: { Line },
	shares: { Share },
	earned: number, -- 오늘 매출
	bill: number, -- 오늘 밤 낸 돈(운영비 + 월세 + 상환금)
	operating: number, -- 그중 운영비
	profit: number, -- 순수익(음수면 적자)
	short: number, -- 지갑으로도 못 메워 빚에 더한 돈
	lateFee: number,
	interest: number,
	due: number, -- 상환금
	debt: number,
	strikes: number,
	bankrupt: boolean,
	survived: number, -- 이번 가게가 며칠까지 버텼는지(파산한 밤이면 그 전날까지)
	newRecords: { number }, -- 이번 밤에 최고 기록을 새로 세운 사람(UserId)
}

local TICK_SECONDS = 0.25

local Days = {}

local layout: Store.Layout? = nil
local phase = "morning" -- morning | countdown | open | night | tutorial
local returnPhase = "morning" -- 튜토리얼이 끝나면 돌아갈 화면
local day = 1
local nextDay = 1
local passed = false -- 그날 흑자였는지(밤 효과음)
local endsAt = 0 -- 카운트다운·영업이 끝나는 때, 밤에는 다음 날이 저절로 시작되는 때
local daySeconds = Config.DaySeconds -- 오늘 영업 시간
local till = 0 -- 가게 금고: 오늘 매출(+ 어제 나누고 남은 잔돈)
local carried = 0 -- 영업 시작 때 금고에 있던 잔돈
local wallets: { [number]: number } = {} -- UserId별 개인 지갑(나갔다 다시 와도 이 서버에서는 남는다)
local bests: { [number]: number } = {} -- UserId별 최고 기록: 며칠까지 버텼는지(Records에 저장)
local today: Today = { sales = 0, tips = 0, served = 0, missed = 0 }
local used: { [string]: number } = {} -- 오늘 영업 중 돈 드는 일을 한 횟수(Stations.onSpend 키별)
local levels: { [string]: number } = {}
local debt = Config.Debt.start
local strikes = 0 -- 연체 횟수
local report: Report? = nil -- 지난밤 정산
local ready: { [Player]: boolean } = {} -- 밤: 다음 날 준비를 누른 사람
local dirty = false -- 운영비가 바뀌어 화면에 보낼 것이 있다(tick에서 모아서 보낸다)

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

local function walletOf(player: Player): number
	return wallets[player.UserId] or 0
end

local function addWallet(player: Player, amount: number)
	wallets[player.UserId] = walletOf(player) + amount
end

-- 아침·밤 화면이 보여 줄 날(밤에는 내일)
local function upcomingDay(): number
	local shown = if phase == "tutorial" then returnPhase else phase
	return if shown == "night" then nextDay else day
end

-- ── 돈 계산 ──

-- 인원이 많으면 월세·상환금이 조금 는다(Config.Costs.perPlayer)
local function fixedScale(): number
	return 1 + Config.Costs.perPlayer * (math.clamp(playerCount(), 1, 4) - 1)
end

local function rent(): number
	return math.floor(Config.Costs.rent * fixedScale() + 0.5)
end

local function interestOn(amount: number): number
	return if amount > 0 then math.ceil(amount * Config.Debt.interest) else 0
end

-- d일 밤에 걷는 상환금(남은 빚보다 많이 걷지 않는 것은 정산할 때 맞춘다)
local function scheduledDue(d: number): number
	return math.floor((Config.Debt.installment + Config.Debt.perDay * (d - 1)) * fixedScale() + 0.5)
end

local function basePower(seconds: number): number
	return math.floor(seconds * Config.Costs.basePower + 0.5)
end

local function entry(name: string, key: string, unit: number): Entry
	return { name = name, count = used[key] or 0, unit = unit }
end

-- 묶음 한 줄: 쓴 항목만 "이름 횟수×값"으로 잇는다
local function line(name: string, entries: { Entry }): Line
	local amount = 0
	local parts = {}
	for _, item in entries do
		if item.count > 0 and item.unit > 0 then
			amount += item.count * item.unit
			table.insert(parts, if item.fixed then `{item.name} {item.unit}` else `{item.name} {item.count}×{item.unit}`)
		end
	end
	return { name = name, amount = amount, detail = table.concat(parts, " · ") }
end

-- 오늘 운영비 장부. seconds를 주면 기본 전기세(영업 시간만큼)도 넣는다.
local function operatingLines(seconds: number?): { Line }
	local costs = Config.Costs
	local food: { Entry } = {}
	for _, id in Config.CrateOrder do
		table.insert(food, entry(Config.Ingredients[id].name, "ing:" .. id, costs.ingredients[id] or 0))
	end
	table.insert(food, entry("콘·컵", "ice:base", costs.ice.base))
	table.insert(food, entry("아이스크림 한 층", "ice:layer", costs.ice.layer))
	table.insert(food, entry("아이스크림 토핑", "ice:topping", costs.ice.topping))
	local power: { Entry } = {}
	if seconds then
		table.insert(power, { name = "기본(조명·냉장고)", count = 1, unit = basePower(seconds), fixed = true })
	end
	table.insert(power, entry("아이스크림 기계", "power:icemachine", costs.power.icemachine or 0))
	for _, kind in { "pot", "grill", "oven" } do
		table.insert(power, entry(Config.Cookers[kind].name, "power:" .. kind, costs.power[kind] or 0))
	end
	return {
		line("재료비", food),
		line("전기·가스", power),
		line("소화기 충전", { entry("소화기", "extinguisher", costs.extinguisher) }),
		line("수도세", { entry("설거지", "wash", costs.wash) }),
		line("쓰레기 봉투", { entry("버리기", "trash", costs.trash) }),
	}
end

local function total(lines: { Line }): number
	local sum = 0
	for _, item in lines do
		sum += item.amount
	end
	return sum
end

-- ── 잠금·효과 ──

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

-- ── 화면에 보내는 상태 ──

local function snapshot()
	local d = upcomingDay()
	local params = Config.dayParams(d, playerCount())
	local seconds = if phase == "open" or phase == "countdown" then daySeconds else params.seconds
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
	local people = {}
	for _, player in Players:GetPlayers() do
		table.insert(people, { userId = player.UserId, name = player.DisplayName, wallet = walletOf(player), best = bests[player.UserId] or 0 })
	end
	local readyIds = {}
	for player in ready do
		table.insert(readyIds, player.UserId)
	end
	return {
		phase = phase,
		day = day,
		upcomingDay = d,
		endsAt = endsAt,
		daySeconds = seconds,
		customers = math.floor(seconds / params.interval + 0.5), -- 오늘(밤에는 내일) 올 손님 어림(인원에 맞춘다)
		till = till,
		people = people,
		today = today,
		passed = passed,
		menus = menus,
		shop = shop,
		rules = rules,
		debt = debt,
		mvp = if phase == "night" then mvp else {},
		-- 오늘 밤 낼 돈: 쓴 운영비(기본 전기세 빼고) + 월세 + 상환금 + 기본 전기세
		money = {
			spent = total(operatingLines(nil)),
			rent = rent(),
			due = math.min(scheduledDue(d), debt + interestOn(debt)),
			basePower = basePower(seconds),
			strikes = strikes,
			maxStrikes = Config.Debt.strikes,
		},
		report = if phase == "night" then report else nil,
		ready = readyIds,
	}
end

local function broadcast()
	dirty = false
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

function Days.start()
	if phase ~= "morning" and phase ~= "night" then
		return
	end
	if phase == "night" then
		day = nextDay
	end
	phase = "countdown"
	passed = false
	today = { sales = 0, tips = 0, served = 0, missed = 0 }
	table.clear(used)
	table.clear(ready)
	carried = till
	stats = {}
	Stations.reset()
	Tables.reset()
	applyEffects()
	endsAt = now() + Config.CountdownSeconds
	daySeconds = Config.dayParams(day, playerCount()).seconds
	broadcast()
end

local function open()
	local params = Config.dayParams(day, playerCount())
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

-- 밤 정산: 빚에 이자를 붙이고, 운영비 + 월세 + 상환금을 금고에서 낸다.
-- 남으면 인원수로 나눠 지갑에(잔돈은 금고에), 모자라면 각자 지갑에서 1/n씩 메우고, 그래도 모자라면 연체.
local function settle(): Report
	local operating = operatingLines(daySeconds)
	local operatingTotal = total(operating)
	local rentNow = rent()
	local scale = fixedScale()
	local interest = interestOn(debt)
	debt += interest
	local due = math.min(scheduledDue(day), debt)
	debt -= due
	local bill = operatingTotal + rentNow + due
	local profit = till - bill
	local members = Players:GetPlayers()
	local count = math.max(1, #members)
	local shares: { Share } = {}
	local short = 0
	if profit >= 0 then
		local each = profit // count
		till = profit - each * #members
		for _, player in members do
			addWallet(player, each)
			table.insert(shares, { userId = player.UserId, name = player.DisplayName, change = each, wallet = walletOf(player) })
		end
	else
		till = 0
		local deficit = -profit
		local each = deficit // count
		local leftover = deficit - each * count -- 나누어떨어지지 않는 몫은 앞사람부터 1씩 더
		local collected = 0
		for i, player in members do
			local pay = math.min(walletOf(player), each + (if i <= leftover then 1 else 0))
			addWallet(player, -pay)
			collected += pay
			table.insert(shares, { userId = player.UserId, name = player.DisplayName, change = -pay, wallet = walletOf(player) })
		end
		short = deficit - collected
	end
	local lateFee = 0
	if short > 0 then
		lateFee = math.ceil(short * Config.Debt.lateFee)
		debt += short + lateFee
		strikes += 1
	end

	local income: { Line } = {
		{ name = "디저트 판매", amount = today.sales - today.tips, detail = `손님 {today.served}명 · 돌아간 손님 {today.missed}명` },
		{ name = "팁·보너스", amount = today.tips, detail = "팁 · 팀 콤보 · 단체 보너스" },
	}
	if carried > 0 then
		table.insert(income, { name = "어제 남은 잔돈", amount = carried, detail = "나누고 남은 금고 돈" })
	end
	local expenses: { Line } = {}
	for _, item in operating do
		if item.amount > 0 then
			table.insert(expenses, item)
		end
	end
	table.insert(expenses, { name = "월세", amount = rentNow, detail = if scale > 1 then `{#members}명이라 +{math.floor((scale - 1) * 100 + 0.5)}%` else "" })
	if due > 0 then
		table.insert(expenses, { name = "빚 상환금", amount = due, detail = `오늘 붙은 이자 +{interest}` })
	end
	return {
		income = income,
		expenses = expenses,
		shares = shares,
		earned = today.sales,
		bill = bill,
		operating = operatingTotal,
		profit = profit,
		short = short,
		lateFee = lateFee,
		interest = interest,
		due = due,
		debt = debt,
		strikes = strikes,
		bankrupt = strikes >= Config.Debt.strikes,
		survived = day,
		newRecords = {},
	}
end

-- 무사히 넘긴 밤: 그날까지 버틴 것을 사람마다 최고 기록과 비교해 저장한다
local function updateRecords(result: Report)
	if result.bankrupt then
		result.survived = day - 1
		return
	end
	for _, player in Players:GetPlayers() do
		if day > (bests[player.UserId] or 0) then
			bests[player.UserId] = day
			table.insert(result.newRecords, player.UserId)
			task.spawn(Records.save, player.UserId, day)
		end
	end
end

-- 들어온 사람의 저장된 최고 기록을 불러온다
local function loadRecord(player: Player)
	task.spawn(function()
		local saved = Records.load(player.UserId)
		bests[player.UserId] = math.max(bests[player.UserId] or 0, saved)
		broadcast()
	end)
end

-- 파산: 처음부터(DAY 1, 지갑·금고 0, 빚·상점 단계·연체 처음으로). 동물(게임패스)은 그대로.
local function goBankrupt()
	nextDay = 1
	till = 0
	table.clear(wallets)
	table.clear(levels)
	debt = Config.Debt.start
	strikes = 0
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
	local result = settle()
	updateRecords(result)
	report = result
	passed = result.profit >= 0
	nextDay = day + 1
	if result.bankrupt then
		goBankrupt()
	end
	phase = "night"
	endsAt = now() + Config.NightSeconds
	table.clear(ready)
	Stations.reset()
	Tables.reset()
	applyEffects()
	local maxStrikes = Config.Debt.strikes
	Remotes.toast(nil, if result.bankrupt then `파산… 연체가 {maxStrikes}번 쌓였어요. DAY 1부터 다시 시작해요`
		elseif result.short > 0 then `돈이 {result.short} 모자라 빚에 더했어요 (연체 {result.strikes}/{maxStrikes})`
		elseif result.profit < 0 then `적자 {-result.profit}, 모두의 지갑에서 나눠 메웠어요`
		else `DAY {day} 정산 끝! 순수익 {result.profit}`)
	broadcast()
end

-- 밤이 끝나면(시간이 다 되거나 모두 준비) 다음 날 영업. 파산한 밤이면 DAY 1 아침으로.
local function endNight()
	local last = report
	if last and last.bankrupt then
		day = nextDay
		phase = "morning"
		passed = false
		table.clear(ready)
		applyEffects()
		broadcast()
	else
		Days.start()
	end
end

-- 밤에 모두 준비했으면 바로 다음 날로
local function checkReady()
	if phase ~= "night" then
		return
	end
	for _, player in Players:GetPlayers() do
		if not ready[player] then
			broadcast()
			return
		end
	end
	endNight()
end

-- 아침: 누가 눌러도 바로 시작. 밤: 준비를 켜고 끄고, 모두 준비하면 시작.
function Days.pressStart(player: Player)
	if phase == "morning" then
		Days.start()
	elseif phase == "night" then
		if ready[player] then
			ready[player] = nil
		else
			ready[player] = true
		end
		checkReady()
	end
end

-- 손님에게 요리를 냈을 때(Main이 Customers.serveAt 성공 뒤 부른다). 판 만큼 바로 금고에 들어온다. 튜토리얼은 세지 않는다.
function Days.earn(price: number, tip: number)
	if phase ~= "open" then
		return
	end
	today.sales += price + tip
	today.tips += tip
	today.served += 1
	till += price + tip
	broadcast()
end

-- 돈 드는 일을 했을 때(Stations.onSpend). 밤 정산에서 Config.Costs 값을 곱해 낸다. 영업 중에만 센다.
function Days.spend(key: string, count: number)
	if phase ~= "open" then
		return
	end
	used[key] = (used[key] or 0) + count
	dirty = true
end

function Days.missed()
	today.missed += 1
	Remotes.toast(nil, "손님이 기다리다 돌아갔어요")
	broadcast()
end

-- 상점: 아침이나 밤에만. 산 사람 지갑에서만 돈이 나가고 효과는 모두에게.
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
			local mine = walletOf(player)
			if not cost then
				Remotes.toast(player, "이미 최고 단계예요")
			elseif mine < cost then
				Remotes.toast(player, `코인이 {cost - mine} 모자라요`)
			else
				addWallet(player, -cost)
				levels[id] = lv + 1
				applyEffects()
				Remotes.toast(nil, `{player.DisplayName}님이 '{upgrade.name}'을(를) 사 줬어요`)
				Remotes.sfx(nil, "buy")
				broadcast()
			end
			return
		end
	end
end

-- 관리자 DAY 패스(테스트용): 영업 중이면 바로 마감(정산은 그대로),
-- 아침·밤이면 정산 없이 바로 다음 DAY 아침으로. 코인은 늘지 않는다.
function Days.adminPass()
	if phase == "open" or phase == "countdown" then
		finish()
		return
	elseif phase ~= "morning" and phase ~= "night" then
		return
	end
	day = if phase == "night" then nextDay else day + 1
	nextDay = day
	phase = "morning"
	passed = false
	today = { sales = 0, tips = 0, served = 0, missed = 0 }
	table.clear(used)
	table.clear(ready)
	Stations.reset()
	Tables.reset()
	applyEffects()
	Remotes.toast(nil, `관리자: DAY {day}로 넘어갔어요`)
	broadcast()
end

-- 관리자 영업 그만하기(테스트용): 영업·튜토리얼 도중에 정산 없이 같은 DAY 아침으로 돌아간다.
-- 그날 번 돈과 쓴 운영비는 없던 걸로 하고, 손님은 돌려보낸다.
function Days.adminStop()
	if phase == "tutorial" then
		Days.endTutorial(false)
		return
	elseif phase ~= "open" and phase ~= "countdown" then
		return
	end
	Customers.stop()
	till = carried
	today = { sales = 0, tips = 0, served = 0, missed = 0 }
	table.clear(used)
	stats = {}
	phase = "morning"
	passed = false
	Stations.reset()
	Tables.reset()
	applyEffects()
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

-- 빚 더 갚기: 아침·밤에만, 갚는 사람 지갑에서. amount는 코인 수 또는 "all"
function Days.payDebt(player: Player, amount: unknown)
	if phase ~= "morning" and phase ~= "night" then
		Remotes.toast(player, "빚은 영업 전·후에 갚아요")
		return
	end
	local want = if amount == "all" then debt elseif typeof(amount) == "number" and amount > 0 then math.floor(amount) else 0
	local pay = math.min(want, debt, walletOf(player))
	if debt <= 0 then
		Remotes.toast(player, "갚을 빚이 없어요")
	elseif pay <= 0 then
		Remotes.toast(player, "코인이 없어요")
	else
		addWallet(player, -pay)
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
	if back == "night" then
		-- 밤 정산 화면으로 돌아오면 다음 날까지 시간을 다시 준다
		endsAt = now() + Config.NightSeconds
		table.clear(ready)
	end
	closeDoorsLater()
	Remotes.toast(nil, if finished then "튜토리얼 끝! 이제 영업을 시작해 봐요" else "튜토리얼을 건너뛰었어요")
	broadcast()
end

local function tick()
	local t = now()
	if phase == "countdown" and t >= endsAt then
		open()
	elseif phase == "open" then
		if t >= endsAt then
			finish()
		elseif dirty then
			broadcast()
		end
	elseif phase == "night" and t >= endsAt then
		endNight()
	end
end

function Days.init(store: Store.Layout)
	layout = store
	Customers.onScriptDone = function()
		Days.endTutorial(true)
	end
	applyEffects()
	local pending = 0
	RunService.Heartbeat:Connect(function(dt: number)
		pending += dt
		if pending >= TICK_SECONDS then
			pending = 0
			tick()
		end
	end)
	-- 인원이 바뀌면 월세·상환금이 바뀐다. 밤에 나가면 남은 사람이 다 준비했는지 다시 본다.
	Players.PlayerAdded:Connect(function(player: Player)
		loadRecord(player)
		broadcast()
	end)
	for _, player in Players:GetPlayers() do
		loadRecord(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		ready[player] = nil
		task.defer(function()
			if phase == "night" then
				checkReady()
			else
				broadcast()
			end
		end)
	end)
end

return Days
