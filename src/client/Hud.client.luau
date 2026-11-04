--!strict
-- 화면(HUD). 영업 중에는 화면을 가리지 않게 맨 위 가운데 작은 바와 오른쪽 작은 버튼만 둔다.
--   맨 위 바: DAY · 남은 시간(손님 말풍선과 겹치지 않게 화면 맨 위에 붙인다)
--   오른쪽 위: 내 코인과 남은 빚. 영업 중에는 오늘 가게 돈의 내 몫까지 실시간으로 오르내린다(liveCoins)
--   오른쪽 버튼: 레시피북(R, 켜고 끄기) · 말풍선(1~4) · 카메라(C) · 끼었어요(처음 자리로) · 관리자 버튼
--   아침·밤: 가운데 창(아침: 오늘 낼 돈·메뉴, 밤: 숫자 카드 + 결과 한 줄, 장부는 접어 둠). 아래 버튼으로 상점 창(Shop)·동물 고르기 창(AnimalPicker)·튜토리얼을 연다.
--   영업이 끝나면 먼저 가운데서 "오늘 번 돈"이 올라가고(Config.NightIntroSeconds) 정산 창이 뜬다.
--   밤에는 Config.NightSeconds 뒤 저절로 다음 날이 시작되고, 모두 준비를 누르면 바로 시작된다.
--   "가게 둘러보기"로 접을 수 있다.
-- 주문은 손님 머리 위 말풍선(Bubbles)이 보여 준다. 판정은 모두 서버가 한다.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

-- ReplicatedStorage는 플레이어 스크립트가 돌기 전에 복제가 끝나 있다(스트리밍 대상은 Workspace뿐)
local Config = require(ReplicatedStorage.Shared.Config)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)
local UiDeco = require(ReplicatedStorage.Shared.UiDeco)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stateEvent = remotes:WaitForChild(Config.Remotes.State) :: RemoteEvent
local toastEvent = remotes:WaitForChild(Config.Remotes.Toast) :: RemoteEvent
local readyEvent = remotes:WaitForChild(Config.Remotes.Ready) :: RemoteEvent
local startEvent = remotes:WaitForChild(Config.Remotes.Start) :: RemoteEvent
local chatEvent = remotes:WaitForChild(Config.Remotes.Chat) :: RemoteEvent
local tutorialEvent = remotes:WaitForChild(Config.Remotes.Tutorial) :: RemoteEvent
local unstuckEvent = remotes:WaitForChild(Config.Remotes.Unstuck) :: RemoteEvent
local adminEvent = remotes:WaitForChild(Config.Remotes.Admin) :: RemoteEvent
local earnedEvent = remotes:WaitForChild(Config.Remotes.Earned) :: RemoteEvent

type MenuView = { dish: string, name: string, steps: string, price: number, isNew: boolean }
type Today = { sales: number, tips: number, served: number, missed: number }
type AnimalView = { name: string, price: number, owned: boolean }
type Person = { userId: number, name: string, wallet: number, best: number, bestSales: number }
-- 오늘 밤 낼 돈: 쓴 운영비(spent, 기본 전기세 빼고) + 월세 + 빚 상환금 + 기본 전기세
type Money = { spent: number, rent: number, due: number, basePower: number, strikes: number, maxStrikes: number }
type Line = { name: string, amount: number, detail: string }
type Share = { userId: number, name: string, change: number, wallet: number }
type Report = {
	income: { Line },
	expenses: { Line },
	shares: { Share },
	earned: number,
	bill: number,
	operating: number,
	profit: number,
	short: number,
	lateFee: number,
	interest: number,
	due: number,
	debt: number,
	strikes: number,
	bankrupt: boolean,
	survived: number,
	newRecords: { number },
	runSales: number,
	runServed: number,
}
type State = {
	phase: string,
	day: number,
	upcomingDay: number,
	endsAt: number,
	daySeconds: number,
	till: number,
	people: { Person },
	today: Today,
	passed: boolean,
	menus: { MenuView },
	animals: { AnimalView },
	rules: { string },
	debt: number,
	money: Money,
	report: Report?,
	ready: { number },
	customers: number,
	toLobby: boolean,
}

local BODY = Enum.Font.GothamBold
local ROUND = Enum.Font.FredokaOne
local INK = Color3.fromRGB(86, 66, 56)
local MUTED = Color3.fromRGB(150, 130, 118)
local PAPER = Color3.fromRGB(255, 251, 244)
local LINE = Color3.fromRGB(236, 220, 202)
local CORAL = Color3.fromRGB(236, 132, 100)
local SAGE = Color3.fromRGB(134, 178, 126)
local GOLD = Color3.fromRGB(232, 176, 76)
local GOLD_TEXT = Color3.fromRGB(196, 140, 48)
local WHITE = Color3.new(1, 1, 1)

local player = Players.LocalPlayer
local state: State = {
	phase = "morning",
	day = 1,
	upcomingDay = 1,
	endsAt = 0,
	daySeconds = 90,
	till = 0,
	people = {},
	today = { sales = 0, tips = 0, served = 0, missed = 0 },
	passed = false,
	menus = {},
	animals = {},
	rules = {},
	debt = 0,
	money = { spent = 0, rent = 0, due = 0, basePower = 0, strikes = 0, maxStrikes = 3 },
	report = nil,
	ready = {},
	customers = 0,
	toLobby = false,
}

local function me(): Person?
	for _, person in state.people do
		if person.userId == player.UserId then
			return person
		end
	end
	return nil
end

local function myWallet(): number
	local mine = me()
	return if mine then mine.wallet else 0
end

-- 오른쪽 위 코인 숫자. 영업 중에는 지갑에 오늘 가게 돈(번 돈 - 쓴 재료비·전기세)의 내 몫(1/n)을 더해서
-- 손님에게 내면 바로 오르고 재료를 쓰면 내려간다. 월세·빚 상환금은 밤 정산에서 빠진다.
local function liveCoins(): number
	local wallet = myWallet()
	if state.phase ~= "open" then
		return wallet
	end
	return wallet + math.floor((state.till - state.money.spent) / math.max(1, #state.people))
end

-- 플레이어 목록·가방은 쓰지 않는다
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

local gui = Instance.new("ScreenGui")
gui.Name = "KitchenHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true -- 바를 화면 맨 위까지 올린다(로블록스 메뉴 버튼은 왼쪽 위에만 있다)
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- ── 만들기 도구 ──

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance)
	local s = Instance.new("UIStroke")
	s.Color = LINE
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function pad(parent: Instance, x: number, y: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, x)
	p.PaddingRight = UDim.new(0, x)
	p.PaddingTop = UDim.new(0, y)
	p.PaddingBottom = UDim.new(0, y)
	p.Parent = parent
end

local function list(parent: Instance, direction: Enum.FillDirection, gap: number): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = direction
	l.Padding = UDim.new(0, gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

local function frame(parent: Instance, size: UDim2): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.BackgroundColor3 = PAPER
	f.BorderSizePixel = 0
	corner(f, 16)
	stroke(f)
	f.Parent = parent
	return f
end

local function text(parent: Instance, value: string, size: number, color: Color3?, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font or BODY
	l.TextSize = size
	l.TextColor3 = color or INK
	l.Text = value
	l.TextWrapped = true
	l.Parent = parent
	return l
end

local function button(parent: Instance, value: string, size: UDim2, color: Color3, textColor: Color3?): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = BODY
	b.TextSize = 16
	b.TextColor3 = textColor or WHITE
	b.Text = value
	b.AutoButtonColor = true
	corner(b, 12)
	b.Parent = parent
	return b
end

-- ── 맨 위 바: DAY · 남은 시간(금고·지출 글과 막대는 글이 많아 뺐다. 돈은 오른쪽 위 코인이 실시간으로 움직인다) ──

local bar = frame(gui, UDim2.fromOffset(176, 52))
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.new(0.5, 0, 0, 4)
bar.Visible = false
local dayChip = text(bar, "DAY 1", 23, CORAL, ROUND)
dayChip.Size = UDim2.fromOffset(92, 52)
local timeLabel = text(bar, "3:00", 23, INK, ROUND)
timeLabel.Size = UDim2.fromOffset(76, 52)
timeLabel.Position = UDim2.fromOffset(88, 0)

-- ── 오른쪽 위: 코인 ──

local coins = frame(gui, UDim2.fromOffset(236, 48))
coins.AnchorPoint = Vector2.new(1, 0)
coins.Position = UDim2.new(1, -10, 0, 4)
local coinIcon = Instance.new("Frame")
coinIcon.Size = UDim2.fromOffset(30, 30)
coinIcon.Position = UDim2.fromOffset(10, 9)
coinIcon.BackgroundColor3 = GOLD
coinIcon.BorderSizePixel = 0
corner(coinIcon, 15)
coinIcon.Parent = coins
local coinMark = Instance.new("UIStroke")
coinMark.Color = Color3.fromRGB(255, 226, 150)
coinMark.Thickness = 3
coinMark.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
coinMark.Parent = coinIcon
local coinLabel = text(coins, "0", 24, GOLD_TEXT, ROUND)
coinLabel.Position = UDim2.fromOffset(48, 0)
coinLabel.Size = UDim2.fromOffset(80, 48)
coinLabel.TextXAlignment = Enum.TextXAlignment.Left
local debtLabel = text(coins, "", 16, MUTED)
debtLabel.Position = UDim2.fromOffset(128, 0)
debtLabel.Size = UDim2.fromOffset(96, 48)
debtLabel.TextXAlignment = Enum.TextXAlignment.Right
-- 코인이 들어오면 "+12"가 떠올랐다 사라진다
local coinGain = text(gui, "", 22, Color3.fromRGB(196, 140, 48), ROUND)
coinGain.AnchorPoint = Vector2.new(1, 0)
coinGain.Size = UDim2.fromOffset(120, 28)
coinGain.TextXAlignment = Enum.TextXAlignment.Right
coinGain.Visible = false
local shownWallet: number? = nil
-- 영업 중 재료·전기를 쓰면 코인 칸 아래로 "-N"이 톡 떨어진다(글자는 안쪽에서 움직이고 자리는 applyScale이 맞춘다)
local spendHolder = Instance.new("Frame")
spendHolder.BackgroundTransparency = 1
spendHolder.AnchorPoint = Vector2.new(1, 0)
spendHolder.Size = UDim2.fromOffset(120, 28)
spendHolder.Parent = gui
local spendLabel = text(spendHolder, "", 20, CORAL, ROUND)
spendLabel.Size = UDim2.fromScale(1, 1)
spendLabel.TextXAlignment = Enum.TextXAlignment.Right
spendLabel.TextTransparency = 1
local spendSum = 0
local spendAt = 0
local function showSpend(amount: number)
	local now = os.clock()
	spendSum = if now - spendAt < 0.8 then spendSum + amount else amount
	spendAt = now
	spendLabel.Text = `-{spendSum}`
	spendLabel.TextTransparency = 0
	spendLabel.Position = UDim2.fromOffset(0, 0)
	TweenService:Create(spendLabel, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(0, 26), TextTransparency = 1 }):Play()
end
-- 숫자가 띠롱띠롱 올라가게: 표시하는 값은 NumberValue를 트윈한다
local coinValue = Instance.new("NumberValue")
coinValue:GetPropertyChangedSignal("Value"):Connect(function()
	coinLabel.Text = tostring(math.floor(coinValue.Value + 0.5))
end)
local coinPop = Instance.new("UIScale")
coinPop.Parent = coinIcon

local toast = text(gui, "", 19, WHITE)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 60)
toast.Size = UDim2.fromOffset(560, 42)
toast.BackgroundColor3 = Color3.fromRGB(96, 78, 68)
toast.BackgroundTransparency = 0.15
corner(toast, 21)
toast.Visible = false

-- ── 오른쪽 버튼: 레시피북 · 말풍선 · 카메라 · 배경음악 · 끼었어요 ──
-- 글자 버튼이 화면을 많이 차지해서 작은 동그란 아이콘으로 두고, 단축키는 작은 배지, 이름은 마우스를 올리면 보인다.

local side = Instance.new("Frame")
side.BackgroundTransparency = 1
side.AnchorPoint = Vector2.new(1, 0)
side.Position = UDim2.new(1, -10, 0, 60)
side.Size = UDim2.fromOffset(46, 7 * 46 + 6 * 8)
side.Parent = gui
list(side, Enum.FillDirection.Vertical, 8)

local tip = text(gui, "", 16, WHITE)
tip.TextWrapped = false -- 버튼에 붙여 띄울 때 버튼 폭에 맞춰 한 글자씩 줄이 바뀌지 않게(글자 길이만큼 넓어진다)
tip.AnchorPoint = Vector2.new(1, 0.5)
tip.AutomaticSize = Enum.AutomaticSize.X
tip.Size = UDim2.fromOffset(0, 32)
tip.BackgroundColor3 = Color3.fromRGB(96, 78, 68)
tip.BackgroundTransparency = 0.1
corner(tip, 16)
pad(tip, 10, 0)
tip.Visible = false

local function iconButton(icon: string, key: string, name: string, order: number): TextButton
	local b = button(side, icon, UDim2.fromOffset(46, 46), PAPER, INK)
	b.LayoutOrder = order
	b.TextSize = 22
	b.Font = Enum.Font.GothamBold
	corner(b, 23)
	stroke(b)
	if key ~= "" then
		local badge = text(b, key, 10, WHITE)
		badge.AnchorPoint = Vector2.new(1, 1)
		badge.Position = UDim2.new(1, 4, 1, 4)
		badge.AutomaticSize = Enum.AutomaticSize.X
		badge.Size = UDim2.fromOffset(0, 16)
		badge.BackgroundColor3 = CORAL
		badge.BackgroundTransparency = 0
		corner(badge, 8)
		pad(badge, 4, 0)
	end
	b.MouseEnter:Connect(function()
		tip.Text = b:GetAttribute("Tip") :: string? or name
		-- 버튼에 붙여 바로 왼쪽에 띄운다. AbsolutePosition으로 계산하면 이 화면(IgnoreGuiInset)에서는
		-- 위쪽 메뉴 바 높이만큼 위로 밀려 화면 끝에 잘렸다.
		tip.Parent = b
		tip.Position = UDim2.new(0, -8, 0.5, 0)
		tip.Visible = true
	end)
	b.MouseLeave:Connect(function()
		tip.Visible = false
	end)
	b:SetAttribute("Tip", name)
	return b
end

local recipeButton = iconButton("📖", "R", "레시피북", 1)
local chatButton = iconButton("💬", "1~4", "말풍선", 2)
local cameraButton = iconButton("🎥", "C", "카메라", 3)
-- 배경음악 켜고 끄기(Music.client가 LocalPlayer 속성 MusicOff를 본다)
local musicButton = iconButton("🎵", "", "배경음악 끄기", 4)
musicButton.Activated:Connect(function()
	local off = player:GetAttribute("MusicOff") ~= true
	player:SetAttribute("MusicOff", off)
	musicButton.Text = if off then "🔇" else "🎵"
	musicButton:SetAttribute("Tip", if off then "배경음악 켜기" else "배경음악 끄기")
end)
-- 구석에 끼었을 때 처음 자리로(들고 있는 것은 그대로)
local unstuckButton = iconButton("🆘", "", "끼었어요: 처음 자리로", 5)
unstuckButton.Activated:Connect(function()
	unstuckEvent:FireServer()
end)
-- 관리자만 보이는 버튼(테스트용). 서버가 다시 관리자인지 확인한다.
--   ⏹ 영업 그만하기(영업·튜토리얼 중에만): 정산 없이 같은 DAY 아침으로
--   ⏭ DAY 패스: 아침·밤이면 정산 없이 다음 DAY 아침으로, 영업 중이면 바로 마감(정산은 그대로)
local stopButton = iconButton("⏹", "", "관리자: 영업 그만하기", 6)
local adminButton = iconButton("⏭", "", "관리자: DAY 패스", 7)
-- 💰 코인 받기(개발자용): 누르면 왼쪽에 작은 창. 칸에 적은 만큼(음수면 뺀다) 또는 +100·+1000·+10000을 바로 받는다.
local coinAdminButton = iconButton("💰", "", "관리자: 코인 받기", 8)
local coinAdmin = frame(coinAdminButton, UDim2.fromOffset(250, 104))
coinAdmin.AnchorPoint = Vector2.new(1, 0)
coinAdmin.Position = UDim2.new(0, -10, 0, 0)
coinAdmin.Visible = false
pad(coinAdmin, 10, 8)
local coinAdminTitle = text(coinAdmin, "코인 받기 (개발자용)", 14, MUTED)
coinAdminTitle.Size = UDim2.new(1, 0, 0, 18)
coinAdminTitle.TextXAlignment = Enum.TextXAlignment.Left
local coinBox = Instance.new("TextBox")
coinBox.Position = UDim2.fromOffset(0, 24)
coinBox.Size = UDim2.new(1, -74, 0, 34)
coinBox.BackgroundColor3 = WHITE
coinBox.BorderSizePixel = 0
coinBox.Font = BODY
coinBox.TextSize = 18
coinBox.TextColor3 = INK
coinBox.PlaceholderText = "코인 수"
coinBox.Text = "1000"
coinBox.ClearTextOnFocus = false
corner(coinBox, 8)
stroke(coinBox)
coinBox.Parent = coinAdmin
local function grant(amount: number?)
	if amount and amount == amount and amount ~= 0 then
		adminEvent:FireServer("coins", math.floor(amount))
	end
end
local coinGive = button(coinAdmin, "받기", UDim2.fromOffset(66, 34), GOLD)
coinGive.AnchorPoint = Vector2.new(1, 0)
coinGive.Position = UDim2.new(1, 0, 0, 24)
coinGive.Activated:Connect(function()
	grant(tonumber(coinBox.Text))
end)
coinBox.FocusLost:Connect(function(enter: boolean)
	if enter then
		grant(tonumber(coinBox.Text))
	end
end)
for i, amount in { 100, 1000, 10000 } do
	local quick = button(coinAdmin, `+{amount}`, UDim2.new(1 / 3, -4, 0, 28), PAPER, GOLD_TEXT)
	quick.Position = UDim2.new((i - 1) / 3, if i == 1 then 0 elseif i == 2 then 2 else 4, 0, 64)
	quick.TextSize = 15
	stroke(quick)
	quick.Activated:Connect(function()
		grant(amount)
	end)
end
coinAdminButton.Activated:Connect(function()
	coinAdmin.Visible = not coinAdmin.Visible
end)
local function updateAdmin()
	local admin = player:GetAttribute("Admin") == true
	local playing = state.phase == "open" or state.phase == "countdown" or state.phase == "tutorial"
	adminButton.Visible = admin
	stopButton.Visible = admin and playing
	coinAdminButton.Visible = admin
	if not admin then
		coinAdmin.Visible = false
	end
end
player:GetAttributeChangedSignal("Admin"):Connect(updateAdmin)
adminButton.Activated:Connect(function()
	adminEvent:FireServer("pass")
end)
stopButton.Activated:Connect(function()
	adminEvent:FireServer("stop")
end)

-- 말풍선 고르기
local chatMenu = Instance.new("Frame")
chatMenu.BackgroundTransparency = 1
chatMenu.AnchorPoint = Vector2.new(1, 0)
chatMenu.Position = UDim2.new(1, -150, 0, 106)
chatMenu.Size = UDim2.fromOffset(140, 4 * 46)
chatMenu.Visible = false
chatMenu.Parent = gui
list(chatMenu, Enum.FillDirection.Vertical, 4)
local function say(index: number)
	chatEvent:FireServer(index)
	chatMenu.Visible = false
end
for i, line in Config.QuickChat do
	local b = button(chatMenu, `{i}  {line}`, UDim2.fromOffset(140, 42), PAPER, INK)
	b.LayoutOrder = i
	b.TextSize = 17
	stroke(b)
	b.Activated:Connect(function()
		say(i)
	end)
end
chatButton.Activated:Connect(function()
	chatMenu.Visible = not chatMenu.Visible
end)
-- 카메라 시점 차례로 바꾸기(C 키와 같다, Camera.client가 그린다)
cameraButton.Activated:Connect(function()
	local modes = Config.CameraModes
	local current = 1
	for i, mode in modes do
		if mode.id == player:GetAttribute("CameraMode") then
			current = i
		end
	end
	player:SetAttribute("CameraMode", modes[current % #modes + 1].id)
end)
local function updateCameraTip()
	for _, mode in Config.CameraModes do
		if mode.id == player:GetAttribute("CameraMode") then
			cameraButton:SetAttribute("Tip", `카메라: {mode.name}`)
		end
	end
end
player:GetAttributeChangedSignal("CameraMode"):Connect(updateCameraTip)
updateCameraTip()

-- 레시피북(켜고 끄기)
local recipe = frame(gui, UDim2.fromOffset(430, 60))
recipe.AnchorPoint = Vector2.new(1, 0)
recipe.Position = UDim2.new(1, -150, 0, 60)
recipe.AutomaticSize = Enum.AutomaticSize.Y
recipe.Visible = false
pad(recipe, 14, 12)
list(recipe, Enum.FillDirection.Vertical, 8)

local function renderRecipe()
	for _, child in recipe:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local title = text(recipe, "레시피북", 22, CORAL, ROUND)
	title.Size = UDim2.new(1, 0, 0, 28)
	title.TextXAlignment = Enum.TextXAlignment.Left
	for i, menu in state.menus do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = i
		row.Parent = recipe
		list(row, Enum.FillDirection.Vertical, 2)
		local name = text(row, `{menu.name}  ·  {menu.price}{if menu.isNew then "  NEW" else ""}`, 18, INK)
		name.Size = UDim2.new(1, 0, 0, 22)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local steps = text(row, menu.steps, 16, MUTED)
		steps.Size = UDim2.new(1, 0, 0, 0)
		steps.AutomaticSize = Enum.AutomaticSize.Y
		steps.TextXAlignment = Enum.TextXAlignment.Left
		steps.LayoutOrder = 1
	end
	local keys = text(recipe, "E 집기·놓기·담기·내기·치우기 / F 길게 조합·토핑·불 끄기·설거지\nR 레시피북 / C 카메라 시점 / 1~4 말풍선", 15, MUTED)
	keys.Size = UDim2.new(1, 0, 0, 0)
	keys.AutomaticSize = Enum.AutomaticSize.Y
	keys.TextXAlignment = Enum.TextXAlignment.Left
	keys.LayoutOrder = 100
end

local function toggleRecipe()
	local recipeScale = recipe:FindFirstChildOfClass("UIScale")
	local opening = not recipe.Visible or (recipeScale ~= nil and UiDeco.isClosing(recipeScale))
	if opening then
		recipe.Visible = true
		chatMenu.Visible = false
		if recipeScale then
			UiDeco.popIn(recipeScale, recipeScale.Scale)
		end
	elseif recipeScale then
		UiDeco.popOut(recipeScale, function()
			recipe.Visible = false
		end)
	else
		recipe.Visible = false
	end
end
recipeButton.Activated:Connect(toggleRecipe)

-- ── 들고 있는 것 ──

local holding = text(gui, "", 19, INK)
holding.AnchorPoint = Vector2.new(0.5, 1)
holding.Position = UDim2.new(0.5, 0, 1, -14)
holding.Size = UDim2.fromOffset(0, 40)
holding.AutomaticSize = Enum.AutomaticSize.X
holding.BackgroundColor3 = PAPER
holding.BackgroundTransparency = 0.05
corner(holding, 20)
pad(holding, 14, 0)
holding.Visible = false
local function updateHolding()
	local value = player:GetAttribute("Holding")
	holding.Visible = typeof(value) == "string"
	holding.Text = if typeof(value) == "string" then `들고 있는 것: {value}` else ""
end
player:GetAttributeChangedSignal("Holding"):Connect(updateHolding)
updateHolding()

-- 플레이 테스트: 740×480에 글씨 17이 작아서 읽기 힘들었다. 창과 글씨를 키우고, 화면에 맞춰 최대 1.5배까지 키운다.
local PANEL_WIDTH = 880
local PANEL_HEIGHT = 600
local NIGHT_HEIGHT = 640 -- 밤 + 장부를 펼쳤을 때(넘치면 장부가 스크롤된다)
local NIGHT_SHORT_HEIGHT = 430 -- 밤 기본: 숫자 카드와 결과 한 줄만
local TOP = 52 -- 제목 아래 내용이 시작하는 높이

-- ── 아침·밤 창: 정산·새 메뉴 + 상점 ──

local center = frame(gui, UDim2.fromOffset(PANEL_WIDTH, PANEL_HEIGHT))
center.AnchorPoint = Vector2.new(0.5, 0.5)
center.Position = UDim2.new(0.5, 0, 0.5, 20) -- 오른쪽 위 코인 칸 아래로
local scale = Instance.new("UIScale")
scale.Parent = center
pad(center, 22, 18)
UiDeco.header(center, 52, 16, Vector2.new(22, 18))

local heading = text(center, "", 36, CORAL, ROUND)
-- 최고 기록(며칠까지 버텼는지): 제목 줄 오른쪽
local recordLabel = text(center, "", 21, Color3.fromRGB(196, 140, 48), ROUND)
recordLabel.AnchorPoint = Vector2.new(1, 0)
recordLabel.Position = UDim2.fromScale(1, 0)
recordLabel.Size = UDim2.fromOffset(380, 42)
recordLabel.TextXAlignment = Enum.TextXAlignment.Right
local recordPop = Instance.new("UIScale")
recordPop.Parent = recordLabel
local recordTween: Tween? = nil
-- 신기록이면 🏆 글자가 콩닥콩닥 커졌다 작아졌다
local function shineRecord(on: boolean)
	if on and not recordTween then
		local tween = TweenService:Create(recordPop, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.12 })
		tween:Play()
		recordTween = tween
	elseif not on and recordTween then
		recordTween:Cancel()
		recordTween = nil
		recordPop.Scale = 1
	end
end

-- ── 새 규칙·새 메뉴 카드 꾸미기 ──
-- 플레이 테스트: 흰 네모 사진 + 글만 있어서 "쇼핑몰 상품 목록" 같았다. 다른 창처럼 아기 분홍·하늘 파스텔에
-- 동그란 배지, NEW! 스티커, 코인 값표, 말랑한 칩으로 꾸민다.
local PINK = Color3.fromRGB(240, 128, 160)
local BABY_PINK = Color3.fromRGB(255, 241, 246)
local RIBBON_PINK = Color3.fromRGB(242, 168, 196)
local SKY = Color3.fromRGB(150, 202, 238)
local SKY_BG = Color3.fromRGB(236, 247, 255)
local SKY_TEXT = Color3.fromRGB(70, 140, 200)

-- frame()이 단 테두리·모서리를 바꾼다
local function restyle(f: GuiObject, color: Color3, thickness: number, radius: number)
	local border = f:FindFirstChildOfClass("UIStroke")
	if border then
		border.Color = color
		border.Thickness = thickness
	end
	local round = f:FindFirstChildOfClass("UICorner")
	if round then
		round.CornerRadius = UDim.new(0, radius)
	end
end

-- 동그란 분홍 배지(하얀 테두리, 살짝 기울임) 안에 그림 글자
local function badge(parent: Instance, icon: string, size: number): TextLabel
	local b = text(parent, icon, math.floor(size * 0.48), WHITE)
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = PINK
	b.BackgroundTransparency = 0
	b.Rotation = -10
	corner(b, size // 2)
	local ring = Instance.new("UIStroke")
	ring.Color = WHITE
	ring.Thickness = 3
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = b
	return b
end

-- 새 규칙 카드(아침 창): 그날 새로 생기는 규칙(글 한 줄로는 눈에 잘 안 띄었다)
local RULE_CARD_HEIGHT = 100
local ruleCard = frame(center, UDim2.new(1, 0, 0, RULE_CARD_HEIGHT))
ruleCard.Position = UDim2.fromOffset(0, TOP)
ruleCard.BackgroundColor3 = BABY_PINK
ruleCard.Visible = false
restyle(ruleCard, RIBBON_PINK, 3, 26)
local ruleIcon = badge(ruleCard, "📢", 56)
ruleIcon.AnchorPoint = Vector2.new(0, 0.5)
ruleIcon.Position = UDim2.new(0, 16, 0.5, 0)
local ruleTitle = text(ruleCard, "새 규칙!", 21, PINK, ROUND)
ruleTitle.Position = UDim2.fromOffset(88, 10)
ruleTitle.Size = UDim2.new(1, -100, 0, 26)
ruleTitle.TextXAlignment = Enum.TextXAlignment.Left
local ruleBody = text(ruleCard, "", 18, INK)
ruleBody.Position = UDim2.fromOffset(88, 38)
ruleBody.Size = UDim2.new(1, -100, 0, 56)
ruleBody.TextXAlignment = Enum.TextXAlignment.Left
ruleBody.TextYAlignment = Enum.TextYAlignment.Top

-- 숫자 카드. 아침: 낼 돈 · 빚 · 연체 · 손님, 밤: 매출 · 낸 돈 · 순수익 · 남은 빚. 글 몇 줄로는 작고 잘 안 보였다.
type Tile = { box: Frame, label: TextLabel, value: TextLabel, sub: TextLabel, pop: UIScale }
local stats = Instance.new("Frame")
stats.BackgroundTransparency = 1
local TILE_HEIGHT = 116
stats.Position = UDim2.fromOffset(0, TOP)
stats.Size = UDim2.new(1, 0, 0, TILE_HEIGHT)
stats.Visible = false
stats.Parent = center
list(stats, Enum.FillDirection.Horizontal, 10)
local tiles: { Tile } = {}
for i = 1, 4 do
	local box = frame(stats, UDim2.new(0.25, -8, 1, 0))
	box.LayoutOrder = i
	box.BackgroundColor3 = Color3.fromRGB(255, 245, 234)
	local label = text(box, "", 18, MUTED)
	label.Position = UDim2.fromOffset(0, 8)
	label.Size = UDim2.new(1, 0, 0, 22)
	local value = text(box, "", 40, INK, ROUND)
	value.Position = UDim2.fromOffset(0, 32)
	value.Size = UDim2.new(1, 0, 0, 46)
	local sub = text(box, "", 16, MUTED)
	sub.Position = UDim2.fromOffset(0, 82)
	sub.Size = UDim2.new(1, 0, 0, 22)
	local pop = Instance.new("UIScale")
	pop.Parent = box
	table.insert(tiles, { box = box, label = label, value = value, sub = sub, pop = pop })
end

-- 새 메뉴 카드: 오늘(아침 창·영업 시작 알림)의 새 메뉴. 동그란 접시 위 디저트 + NEW! 스티커,
-- 이름 옆 코인 값표, 만드는 순서는 칩(반죽 ▸ 조합대 ▸ …)으로 보여 준다.
local MENU_CARD_HEIGHT = 112
local menuCard = frame(center, UDim2.new(1, 0, 0, MENU_CARD_HEIGHT))
menuCard.BackgroundColor3 = SKY_BG
menuCard.Visible = false
restyle(menuCard, SKY, 3, 26)
-- 접시: 하얀 동그라미 + 하늘 테두리 + 안쪽 연한 원. 디저트(ViewportFrame)는 배경 없이 그 위에 올린다.
-- (ViewportFrame에는 둥근 모서리가 안 먹어서 검은 테두리 네모로 보였다)
local plate = Instance.new("Frame")
plate.Position = UDim2.fromOffset(14, 10)
plate.Size = UDim2.fromOffset(92, 92)
plate.BackgroundColor3 = WHITE
plate.BorderSizePixel = 0
corner(plate, 46)
local plateRing = Instance.new("UIStroke")
plateRing.Color = SKY
plateRing.Thickness = 4
plateRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
plateRing.Parent = plate
plate.Parent = menuCard
local plateInner = Instance.new("Frame")
plateInner.AnchorPoint = Vector2.new(0.5, 0.5)
plateInner.Position = UDim2.fromScale(0.5, 0.5)
plateInner.Size = UDim2.fromScale(0.76, 0.76)
plateInner.BackgroundColor3 = Color3.fromRGB(246, 251, 255)
plateInner.BorderSizePixel = 0
corner(plateInner, 35)
plateInner.Parent = plate
local menuView = Instance.new("ViewportFrame")
menuView.BackgroundTransparency = 1
menuView.BorderSizePixel = 0
menuView.Size = UDim2.fromScale(1, 1)
menuView.Ambient = Color3.fromRGB(200, 190, 196)
menuView.LightColor = Color3.fromRGB(255, 246, 250)
menuView.LightDirection = Vector3.new(-1, -2, -1)
menuView.Parent = plate
-- NEW! 스티커: 접시 왼쪽 위에 비스듬히, 살랑살랑 흔들린다
local newTag = text(menuCard, "NEW!", 15, WHITE, ROUND)
newTag.Size = UDim2.fromOffset(58, 24)
newTag.Position = UDim2.fromOffset(2, 4)
newTag.BackgroundColor3 = PINK
newTag.BackgroundTransparency = 0
newTag.Rotation = -14
newTag.ZIndex = 3
corner(newTag, 12)
local newRing = Instance.new("UIStroke")
newRing.Color = WHITE
newRing.Thickness = 2
newRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
newRing.Parent = newTag
TweenService:Create(newTag, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = -4 }):Play()
for _, spot in { { 98, 6, 18 }, { 96, 82, 14 } } do
	local sparkle = text(menuCard, "✨", spot[3])
	sparkle.Position = UDim2.fromOffset(spot[1], spot[2])
	sparkle.Size = UDim2.fromOffset(22, 22)
	sparkle.ZIndex = 3
end
local menuTitle = text(menuCard, "", 18, SKY_TEXT, ROUND)
menuTitle.Position = UDim2.fromOffset(124, 8)
menuTitle.Size = UDim2.new(1, -136, 0, 22)
menuTitle.TextXAlignment = Enum.TextXAlignment.Left
-- 이름 + 코인 값표(메뉴마다)
local menuNames = Instance.new("Frame")
menuNames.BackgroundTransparency = 1
menuNames.Position = UDim2.fromOffset(124, 32)
menuNames.Size = UDim2.new(1, -136, 0, 34)
menuNames.Parent = menuCard
list(menuNames, Enum.FillDirection.Horizontal, 10).VerticalAlignment = Enum.VerticalAlignment.Center
-- 만드는 순서 칩
local menuSteps = Instance.new("Frame")
menuSteps.BackgroundTransparency = 1
menuSteps.Position = UDim2.fromOffset(124, 72)
menuSteps.Size = UDim2.new(1, -136, 0, 28)
menuSteps.Parent = menuCard
list(menuSteps, Enum.FillDirection.Horizontal, 4).VerticalAlignment = Enum.VerticalAlignment.Center
local shownDish = ""

-- 아이스크림은 맛이 정해져 있지 않아서 보기 좋은 한 가지로 그린다
local SAMPLE_ICE: Config.IceSpec = { base = "cone", flavors = { "strawberry", "vanilla" }, topping = "sprinkles" }

local function clearItems(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- 글자 길이만큼 넓어지는 동글동글 칩
local function pill(parent: Instance, value: string, size: number, color: Color3, fill: Color3, edge: Color3?, height: number): TextLabel
	local chip = text(parent, value, size, color)
	chip.TextWrapped = false
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromOffset(0, height)
	chip.BackgroundColor3 = fill
	chip.BackgroundTransparency = 0
	corner(chip, height // 2)
	pad(chip, 9, 0)
	if edge then
		local ring = Instance.new("UIStroke")
		ring.Color = edge
		ring.Thickness = 2
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = chip
	end
	return chip
end

local function showMenuCard(menus: { MenuView }, title: string)
	local first = menus[1]
	menuTitle.Text = title
	clearItems(menuNames)
	local order = 0
	for _, menu in menus do
		order += 1
		local name = text(menuNames, menu.name, 24, INK, ROUND)
		name.TextWrapped = false
		name.AutomaticSize = Enum.AutomaticSize.X
		name.Size = UDim2.fromOffset(0, 34)
		name.LayoutOrder = order
		-- 코인 값표: 연노랑 알약 안에 금색 동전 + 값
		order += 1
		local price = Instance.new("Frame")
		price.AutomaticSize = Enum.AutomaticSize.X
		price.Size = UDim2.fromOffset(0, 28)
		price.BackgroundColor3 = Color3.fromRGB(255, 243, 210)
		price.BorderSizePixel = 0
		price.LayoutOrder = order
		corner(price, 14)
		local priceEdge = Instance.new("UIStroke")
		priceEdge.Color = Color3.fromRGB(246, 214, 140)
		priceEdge.Thickness = 2
		priceEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		priceEdge.Parent = price
		pad(price, 7, 0)
		list(price, Enum.FillDirection.Horizontal, 5).VerticalAlignment = Enum.VerticalAlignment.Center
		price.Parent = menuNames
		local coin = Instance.new("Frame")
		coin.Size = UDim2.fromOffset(18, 18)
		coin.BackgroundColor3 = GOLD
		coin.BorderSizePixel = 0
		coin.LayoutOrder = 1
		corner(coin, 9)
		local coinEdge = Instance.new("UIStroke")
		coinEdge.Color = Color3.fromRGB(255, 226, 150)
		coinEdge.Thickness = 2
		coinEdge.Parent = coin
		coin.Parent = price
		local priceText = text(price, tostring(menu.price), 18, GOLD_TEXT, ROUND)
		priceText.TextWrapped = false
		priceText.AutomaticSize = Enum.AutomaticSize.X
		priceText.Size = UDim2.fromOffset(0, 28)
		priceText.LayoutOrder = 2
	end
	clearItems(menuSteps)
	local steps = string.split(first.steps, " → ")
	for i, step in steps do
		if i > 1 then
			local arrow = text(menuSteps, "▸", 13, PINK)
			arrow.Size = UDim2.fromOffset(12, 26)
			arrow.LayoutOrder = i * 2 - 1
		end
		local chip = pill(menuSteps, step, 14, INK, WHITE, SKY, 26)
		chip.LayoutOrder = i * 2
	end
	if shownDish ~= first.dish then
		shownDish = first.dish
		menuView:ClearAllChildren()
		local model = FoodModels.build(first.dish, Config.servedState(first.dish), 0, if first.dish == "icecream" then SAMPLE_ICE else nil)
		model.Parent = menuView
		local root = model.PrimaryPart :: BasePart
		local reach = math.max(root.Size.X, root.Size.Y, root.Size.Z)
		local camera = Instance.new("Camera")
		camera.FieldOfView = 34
		camera.CFrame = CFrame.lookAt(Vector3.new(0, reach * 1.1, reach * 2.1), Vector3.new(0, 0, 0))
		camera.Parent = menuView
		menuView.CurrentCamera = camera
	end
end
-- 그날(아침·영업) 또는 내일(밤) 새로 나온 메뉴
local function freshMenus(): { MenuView }
	local fresh = {}
	for _, menu in state.menus do
		if menu.isNew then
			table.insert(fresh, menu)
		end
	end
	return fresh
end

local function setTile(index: number, label: string, value: string, color: Color3, sub: string)
	local tile = tiles[index]
	tile.label.Text = label
	tile.value.Text = value
	tile.value.TextColor3 = color
	tile.sub.Text = sub
end
heading.Size = UDim2.new(1, 0, 0, 42)
heading.TextXAlignment = Enum.TextXAlignment.Left

-- 글이 길면 이 칸 안에서 스크롤된다(아래 버튼과 겹치지 않게)
local summaryBox = Instance.new("ScrollingFrame")
summaryBox.BackgroundTransparency = 1
summaryBox.BorderSizePixel = 0
summaryBox.Position = UDim2.fromOffset(0, TOP)
summaryBox.Size = UDim2.new(1, 0, 1, -(TOP + 72))
summaryBox.CanvasSize = UDim2.new()
summaryBox.AutomaticCanvasSize = Enum.AutomaticSize.Y
summaryBox.ScrollBarThickness = 6
summaryBox.ScrollBarImageColor3 = LINE
summaryBox.Parent = center
list(summaryBox, Enum.FillDirection.Vertical, 10)
local summary = text(summaryBox, "", 22, INK)
summary.Size = UDim2.new(1, -12, 0, 0)
summary.AutomaticSize = Enum.AutomaticSize.Y
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.TextYAlignment = Enum.TextYAlignment.Top
summary.RichText = true
summary.LineHeight = 1.15
-- 밤 정산 장부는 접어 둔다(플레이 테스트: 글이 너무 많아 안 읽혔다). 궁금하면 이 버튼으로 펼친다.
local ledgerOpen = false
local ledgerToggle = button(summaryBox, "", UDim2.fromOffset(200, 36), PAPER, MUTED)
ledgerToggle.LayoutOrder = 1
ledgerToggle.Visible = false
stroke(ledgerToggle)
-- 밤 정산 장부: 왼쪽 들어온 돈·나눠 가진 돈, 오른쪽 나간 돈·빚
local ledger = Instance.new("Frame")
ledger.BackgroundTransparency = 1
ledger.Size = UDim2.new(1, -12, 0, 0)
ledger.AutomaticSize = Enum.AutomaticSize.Y
ledger.LayoutOrder = 2
ledger.Visible = false
ledger.Parent = summaryBox
list(ledger, Enum.FillDirection.Horizontal, 20)
local function ledgerColumn(order: number): TextLabel
	local column = text(ledger, "", 20, INK)
	column.LayoutOrder = order
	column.Size = UDim2.new(0.5, -10, 0, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.TextXAlignment = Enum.TextXAlignment.Left
	column.TextYAlignment = Enum.TextYAlignment.Top
	column.RichText = true
	column.LineHeight = 1.1
	return column
end
local ledgerIn = ledgerColumn(1)
local ledgerOut = ledgerColumn(2)

local startButton = button(center, "", UDim2.fromOffset(220, 54), CORAL)
startButton.AnchorPoint = Vector2.new(1, 1)
startButton.Position = UDim2.fromScale(1, 1)
startButton.TextSize = 20
startButton.Activated:Connect(function()
	startEvent:FireServer()
end)
-- 밤: 준비한 사람 수와 다음 날이 저절로 시작될 때까지 남은 시간(시작 버튼 위)
local readyLabel = text(center, "", 18, MUTED)
readyLabel.AnchorPoint = Vector2.new(1, 1)
readyLabel.Position = UDim2.new(1, 0, 1, -60)
readyLabel.Size = UDim2.fromOffset(360, 22)
readyLabel.TextXAlignment = Enum.TextXAlignment.Right
readyLabel.Visible = false
local browseButton = button(center, "가게 둘러보기", UDim2.fromOffset(130, 54), PAPER, INK)
browseButton.AnchorPoint = Vector2.new(0, 1)
browseButton.Position = UDim2.fromScale(0, 1)
browseButton.TextSize = 18
stroke(browseButton)
-- 내 동물 고르기: 동물 고르기 창(AnimalPicker)을 연다. 창은 LocalPlayer 속성 AnimalPicker만 본다.
local animalButton = button(center, "동물 고르기", UDim2.fromOffset(196, 54), PAPER, INK)
animalButton.AnchorPoint = Vector2.new(0, 1)
animalButton.Position = UDim2.new(0, 140, 1, 0)
animalButton.TextSize = 17
stroke(animalButton)
animalButton.Activated:Connect(function()
	player:SetAttribute("AnimalPicker", true)
end)
local function updateAnimal()
	local name = player:GetAttribute("Animal")
	animalButton.Text = if typeof(name) == "string" then `동물 고르기 · {name}` else "동물 고르기"
end
-- 연습 손님 두 명으로 하는 튜토리얼(코인은 들어오지 않는다)
-- 상점 창(Shop): 그림과 함께 스킬·기구, 빚 갚기. 창은 LocalPlayer 속성 ShopOpen만 본다.
local shopButton = button(center, "상점", UDim2.fromOffset(110, 54), GOLD)
shopButton.AnchorPoint = Vector2.new(0, 1)
shopButton.Position = UDim2.new(0, 346, 1, 0)
shopButton.TextSize = 18
shopButton.Activated:Connect(function()
	player:SetAttribute("ShopOpen", true)
end)
local tutorialButton = button(center, "튜토리얼", UDim2.fromOffset(110, 54), PAPER, CORAL)
tutorialButton.AnchorPoint = Vector2.new(0, 1)
tutorialButton.Position = UDim2.new(0, 466, 1, 0)
tutorialButton.TextSize = 17
stroke(tutorialButton)
tutorialButton.Activated:Connect(function()
	tutorialEvent:FireServer(true)
end)
player:GetAttributeChangedSignal("Animal"):Connect(updateAnimal)
updateAnimal()

-- 창을 접었을 때 다시 여는 버튼
local reopen = button(gui, "준비 화면 열기", UDim2.fromOffset(200, 50), CORAL)
reopen.TextSize = 19
reopen.AnchorPoint = Vector2.new(0.5, 1)
reopen.Position = UDim2.new(0.5, 0, 1, -56)
reopen.Visible = false

local panelHidden = false

-- 아래 버튼 줄. 가게 둘러보기·튜토리얼은 처음 시작할 때(DAY 1 아침)만 보인다. 보이는 것만 왼쪽부터 붙인다.
local function layoutButtons(firstMorning: boolean)
	browseButton.Visible = firstMorning
	tutorialButton.Visible = firstMorning
	local x = 0
	for _, b in { browseButton, animalButton, shopButton, tutorialButton } do
		if b.Visible then
			b.Position = UDim2.new(0, x, 1, 0)
			x += b.Size.X.Offset + 10
		end
	end
end

-- 3·2·1: 크림색 동그라미에 숫자마다 다른 색 테두리. 숫자가 바뀔 때마다 톡 튀어나오고, 끝나면 "오픈!"
local COUNT_COLORS = { CORAL, GOLD, SAGE }
local OPEN_COLOR = Color3.fromRGB(240, 128, 160)
local countdown = Instance.new("Frame")
countdown.ZIndex = 40 -- 날짜 넘어가는 커튼 위에
countdown.AnchorPoint = Vector2.new(0.5, 0.5)
countdown.Position = UDim2.fromScale(0.5, 0.56) -- 위쪽 새 규칙·새 메뉴 알림과 겹치지 않게
countdown.Size = UDim2.fromOffset(170, 170)
countdown.BackgroundColor3 = PAPER
countdown.BorderSizePixel = 0
countdown.Visible = false
corner(countdown, 85)
countdown.Parent = gui
local countRing = Instance.new("UIStroke")
countRing.Thickness = 10
countRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
countRing.Parent = countdown
local countPop = Instance.new("UIScale")
countPop.Parent = countdown
local countNumber = text(countdown, "", 108, CORAL, ROUND)
countNumber.Size = UDim2.fromScale(1, 1)
local countSeq = 0
local shownCount = 0

local function popCount(label: string, color: Color3, size: number)
	countdown.Visible = true
	countNumber.Text = label
	countNumber.TextSize = size
	countNumber.TextColor3 = color
	countRing.Color = color
	countPop.Scale = 1.7
	countdown.Rotation = -14
	local info = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(countPop, info, { Scale = 1 }):Play()
	TweenService:Create(countdown, info, { Rotation = 0 }):Play()
end

local function showCount(n: number)
	if n == shownCount then
		return
	end
	shownCount = n
	countSeq += 1
	popCount(tostring(n), COUNT_COLORS[math.clamp(n, 1, #COUNT_COLORS)], 108)
end

local function hideCount()
	countSeq += 1
	shownCount = 0
	countdown.Visible = false
end

-- 영업 시작: "오픈!"을 잠깐 보여 주고 쏙 들어간다
local function showOpen()
	countSeq += 1
	local seq = countSeq
	shownCount = 0
	popCount("오픈!", OPEN_COLOR, 48)
	task.delay(0.7, function()
		if seq ~= countSeq then
			return
		end
		TweenService:Create(countPop, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.delay(0.2, function()
			if seq == countSeq then
				countdown.Visible = false
			end
		end)
	end)
end

-- 영업 끝: 정산 창 전에 가게 화면 가운데서 "오늘 번 돈"이 코인과 함께 올라간다(Config.NightIntroSeconds)
local earnedShow = Instance.new("Frame")
earnedShow.BackgroundTransparency = 1
earnedShow.AnchorPoint = Vector2.new(0.5, 0.5)
earnedShow.Position = UDim2.fromScale(0.5, 0.42)
earnedShow.Size = UDim2.fromOffset(560, 180)
earnedShow.Visible = false
earnedShow.Parent = gui
local earnedPop = Instance.new("UIScale")
earnedPop.Parent = earnedShow
local earnedTitle = text(earnedShow, "오늘 번 돈", 34, WHITE, ROUND)
earnedTitle.Size = UDim2.new(1, 0, 0, 46)
local titleStroke = Instance.new("UIStroke")
titleStroke.Color = INK
titleStroke.Thickness = 3
titleStroke.Parent = earnedTitle
local earnedRow = Instance.new("Frame")
earnedRow.BackgroundTransparency = 1
earnedRow.Position = UDim2.fromOffset(0, 54)
earnedRow.Size = UDim2.new(1, 0, 0, 120)
earnedRow.Parent = earnedShow
local earnedRowList = list(earnedRow, Enum.FillDirection.Horizontal, 18)
earnedRowList.HorizontalAlignment = Enum.HorizontalAlignment.Center
earnedRowList.VerticalAlignment = Enum.VerticalAlignment.Center
-- 큰 코인: 오른쪽 위 코인과 같은 모양(금색 동그라미 + 연한 테두리)에 안쪽 고리. 셀 동안 빙글빙글 뒤집힌다.
local bigCoinHolder = Instance.new("Frame")
bigCoinHolder.BackgroundTransparency = 1
bigCoinHolder.Size = UDim2.fromOffset(100, 100)
bigCoinHolder.LayoutOrder = 1
bigCoinHolder.Parent = earnedRow
local bigCoin = Instance.new("Frame")
bigCoin.AnchorPoint = Vector2.new(0.5, 0.5)
bigCoin.Position = UDim2.fromScale(0.5, 0.5)
bigCoin.Size = UDim2.fromScale(1, 1)
bigCoin.BackgroundColor3 = GOLD
bigCoin.BorderSizePixel = 0
corner(bigCoin, 50)
bigCoin.Parent = bigCoinHolder
local bigCoinEdge = Instance.new("UIStroke")
bigCoinEdge.Color = Color3.fromRGB(255, 226, 150)
bigCoinEdge.Thickness = 7
bigCoinEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
bigCoinEdge.Parent = bigCoin
local bigCoinRing = Instance.new("Frame")
bigCoinRing.AnchorPoint = Vector2.new(0.5, 0.5)
bigCoinRing.Position = UDim2.fromScale(0.5, 0.5)
bigCoinRing.Size = UDim2.fromScale(0.6, 0.6)
bigCoinRing.BackgroundTransparency = 1
corner(bigCoinRing, 30)
bigCoinRing.Parent = bigCoin
local bigCoinInner = Instance.new("UIStroke")
bigCoinInner.Color = Color3.fromRGB(214, 150, 52)
bigCoinInner.Thickness = 4
bigCoinInner.Parent = bigCoinRing
local earnedNumber = text(earnedRow, "+0", 100, GOLD, ROUND)
earnedNumber.LayoutOrder = 2
earnedNumber.TextWrapped = false
earnedNumber.AutomaticSize = Enum.AutomaticSize.X
earnedNumber.Size = UDim2.fromOffset(0, 120)
local numberStroke = Instance.new("UIStroke")
numberStroke.Color = WHITE
numberStroke.Thickness = 6
numberStroke.Parent = earnedNumber
local numberPop = Instance.new("UIScale")
numberPop.Parent = earnedNumber
local earnedValue = Instance.new("NumberValue")
earnedValue:GetPropertyChangedSignal("Value"):Connect(function()
	earnedNumber.Text = `+{math.floor(earnedValue.Value + 0.5)}`
end)
local introSeq = 0
local introPlaying = false

-- 형광펜: 중요한 말 뒤에 연분홍(경고·빚)이나 연하늘(낼 돈·메뉴) 배경을 깐다(RichText mark)
local function pink(value: string): string
	return `<mark color="#ffd6e4" transparency="0">{value}</mark>`
end
local function sky(value: string): string
	return `<mark color="#d2eafb" transparency="0">{value}</mark>`
end

local function signed(n: number): string
	return if n >= 0 then `+{n}` else tostring(n)
end

-- 장부 한 묶음: "이름  금액", 다음 줄에 흐린 글씨로 자세히
local function ledgerLines(lines: { Line }, sign: string): string
	local out = {}
	for _, item in lines do
		local row = `{item.name}  <b>{sign}{item.amount}</b>`
		if item.detail ~= "" then
			row ..= `\n<font size="17" color="#968276">{item.detail}</font>`
		end
		table.insert(out, row)
	end
	return table.concat(out, "\n")
end

local function myShare(r: Report): Share?
	for _, share in r.shares do
		if share.userId == player.UserId then
			return share
		end
	end
	return nil
end

-- 밤: 시작 버튼은 준비 켜고 끄기(모두 준비하면 바로 시작), 위에는 준비한 사람 수와 저절로 시작될 때까지 남은 시간
local function updateNightButton()
	local r = state.report
	local left = math.max(0, math.ceil(state.endsAt - workspace:GetServerTimeNow()))
	local mine = table.find(state.ready, player.UserId) ~= nil
	local total = math.max(1, #state.people)
	local d = state.upcomingDay
	if r and r.bankrupt then
		-- 게임 끝: 로비로 돌아간다(로비가 없으면 이 서버에서 DAY 1부터)
		startButton.Text = if mine then "준비 완료!" elseif state.toLobby then "로비로 돌아가기" else "DAY 1 아침으로"
		readyLabel.Text = `{left}초 뒤 {if state.toLobby then "로비로" else "처음부터"} · 준비 {#state.ready}/{total}`
	elseif total > 1 then
		startButton.Text = if mine then "준비 완료!" else `DAY {d} 준비`
		readyLabel.Text = `준비 {#state.ready}/{total} · {left}초 뒤 DAY {d} 시작`
	else
		startButton.Text = `DAY {d} 바로 시작`
		readyLabel.Text = `{left}초 뒤 DAY {d} 영업이 시작돼요`
	end
	startButton.BackgroundColor3 = if mine then SAGE else CORAL
end

-- 밤 정산: 숫자 카드, 한 줄 결과, 장부(들어온 돈·나눠 가진 돈 / 나간 돈·빚)
local function renderNight(r: Report)
	local today = state.today
	local maxStrikes = state.money.maxStrikes
	local status = if r.bankrupt
		then `<font color="#e0705a">파산…</font>`
		elseif r.short > 0 then `<font color="#e0705a">연체 {r.strikes}/{maxStrikes}</font>`
		elseif r.profit < 0 then `<font color="#e0705a">적자</font>`
		else `<font color="#6fa868">흑자!</font>`
	heading.Text = `DAY {state.day} 정산   {status}`
	local mineNow = me()
	local mine = myShare(r)
	local mineText = if not mine then "" elseif r.profit >= 0 then `내 몫 +{mine.change}` else `내가 메운 돈 {-mine.change}`
	if r.bankrupt then
		-- 최종 결과: 이번 가게가 버틴 날, 연 뒤 총 매출·받은 손님, 내 최고 기록
		setTile(1, "버틴 날", `DAY {r.survived}`, CORAL, if r.survived > 0 then `{r.survived}일 동안 영업` else "첫날 파산")
		setTile(2, "총 매출", tostring(r.runSales), GOLD, `손님 {r.runServed}명`)
		setTile(3, "오늘 순수익", signed(r.profit), if r.profit >= 0 then SAGE else CORAL, mineText)
		setTile(4, "최고 기록", if mineNow and mineNow.best > 0 then `DAY {mineNow.best}` else "-", INK, if mineNow and mineNow.best > 0 then `매출 {mineNow.bestSales}` else "")
	else
		setTile(1, "오늘 매출", `+{r.earned}`, GOLD, `손님 {today.served}명 · 돌아간 {today.missed}명`)
		setTile(2, "오늘 낸 돈", `-{r.bill}`, CORAL, `운영비 {r.operating} · 월세·상환 {r.bill - r.operating}`)
		setTile(3, "순수익", signed(r.profit), if r.profit >= 0 then SAGE else CORAL, mineText)
		setTile(4, "남은 빚", tostring(r.debt), if r.strikes > 0 then CORAL else INK, if r.strikes > 0 then `연체 {r.strikes}/{maxStrikes}` else "연체 없음")
	end

	-- 결과는 한 줄만: 숫자는 위 카드에 있고, 자세한 건 접힌 장부에 있다
	local count = #r.shares
	local result: string
	if r.bankrupt then
		local next = if state.toLobby then "로비에서 다시 팀을 짜고 새 가게를 열어요." else "DAY 1부터 다시 시작해요. (지갑·빚·상점 처음으로)"
		result = `{pink(`<b>연체 {maxStrikes}번! 가게가 문을 닫았어요.</b>`)}\n{next}`
	elseif r.short > 0 then
		result = `{pink(`<b>⚠ {r.short} 모자라서 빚에 더했어요</b>`)}  ({maxStrikes}번 연체면 파산!)`
	elseif r.profit < 0 then
		result = `적자 {-r.profit}은 {if count > 1 then `{count}명이 1/n씩` else "내 지갑에서"} 메웠어요.`
	elseif count > 1 then
		result = `순수익을 {count}명이 똑같이 나눠 가졌어요.`
	else
		result = `순수익이 내 지갑에 들어왔어요.`
	end
	summary.Text = result
	-- 신기록은 따로 줄을 쓰지 않고 오른쪽 위 🏆 자리에 띄운다(콩닥콩닥)
	local isNew = table.find(r.newRecords, player.UserId) ~= nil
	if isNew then
		recordLabel.Text = `✨🏆 신기록! DAY {r.survived} · 매출 {r.runSales}`
	end
	shineRecord(isNew)

	local incomeTotal = 0
	for _, item in r.income do
		incomeTotal += item.amount
	end
	local left = `<font color="#c48c30"><b>들어온 돈  +{incomeTotal}</b></font>\n{ledgerLines(r.income, "+")}`
	if count > 0 then
		local rows = {}
		for _, share in r.shares do
			table.insert(rows, `{share.name}  <b>{signed(share.change)}</b>  <font color="#968276">→ 지갑 {share.wallet}</font>`)
		end
		left ..= `\n\n<b>{if r.profit >= 0 then "나눠 가진 돈" else "메운 돈"}</b>\n{table.concat(rows, "\n")}`
	end
	if state.till > 0 then
		left ..= `\n<font size="17" color="#968276">잔돈 {state.till}은 금고에 남겨 내일 매출에 더해요</font>`
	end
	ledgerIn.Text = left
	local debtLine = if r.debt <= 0 and r.short <= 0
		then sky("<b>빚 없음!</b>")
		else `<b>빚</b>  이자 +{r.interest} · 상환 -{r.due}{if r.short > 0 then ` · 못 낸 돈 +{r.short} · 연체료 +{r.lateFee}` else ""}\n→ {pink(`남은 빚 <b>{r.debt}</b>`)}`
	ledgerOut.Text = `<font color="#e0705a"><b>나간 돈  -{r.bill}</b></font>\n{ledgerLines(r.expenses, "-")}\n\n{debtLine}`
	updateNightButton()
end

local function renderCenter()
	local phase = state.phase
	local d = state.upcomingDay
	local report = state.report
	local night = phase == "night" and report ~= nil
	center.Size = UDim2.fromOffset(PANEL_WIDTH, if not night then PANEL_HEIGHT elseif ledgerOpen then NIGHT_HEIGHT else NIGHT_SHORT_HEIGHT)
	-- 새 규칙·새 메뉴 카드는 아침에만. 밤에는 장부 자리가 좁아서 빼고, 영업을 시작할 때 화면 위에 잠깐 보여 준다(showAnnounce).
	local hasRules = #state.rules > 0 and not night
	-- 위에서부터: 숫자 카드 → (아침) 새 규칙 카드 → 새 메뉴 카드 → 글·장부
	local y = TOP + TILE_HEIGHT + 10
	stats.Visible = true
	ledger.Visible = night and ledgerOpen
	ledgerToggle.Visible = night
	ledgerToggle.Text = if ledgerOpen then "장부 접기 ▴" else "장부 자세히 보기 ▾"
	summary.TextSize = if night then 24 else 22
	readyLabel.Visible = night
	local mine = me()
	recordLabel.Text = if mine and mine.best > 0 then `🏆 최고 DAY {mine.best} · 매출 {mine.bestSales}` else "🏆 첫 도전!"
	ruleCard.Visible = hasRules
	ruleCard.Position = UDim2.fromOffset(0, y)
	ruleTitle.Text = "새 규칙!"
	ruleBody.Text = table.concat(state.rules, " ")
	if hasRules then
		y += RULE_CARD_HEIGHT + 10
	end
	local fresh = freshMenus()
	local showMenus = #fresh > 0 and not night
	if showMenus then
		menuCard.Parent = center
		menuCard.Visible = true
		menuCard.Position = UDim2.fromOffset(0, y)
		showMenuCard(fresh, "🍨 오늘의 새 메뉴!")
		y += MENU_CARD_HEIGHT + 10
	elseif menuCard.Parent == center then
		menuCard.Visible = false
	end
	summaryBox.Position = UDim2.fromOffset(0, y)
	summaryBox.Size = UDim2.new(1, 0, 1, -(y + (if night then 92 else 72)))
	summaryBox.CanvasPosition = Vector2.zero
	heading.RichText = true
	if report and night then
		layoutButtons(false)
		renderNight(report)
		return
	end
	-- 아침: 숫자 카드와 짧은 안내만(메뉴 조합·키 설명은 레시피북 R에 있다)
	layoutButtons(phase == "morning" and d == 1)
	heading.Text = `DAY {d}`
	local money = state.money
	setTile(1, "오늘 밤 낼 돈", `{money.rent + money.due + money.basePower}+`, CORAL, "고정비 + 쓴 만큼")
	setTile(2, "남은 빚", if state.debt > 0 then tostring(state.debt) else "없음", INK, `이자 {math.floor(Config.Debt.interest * 100 + 0.5)}% · 상환 {money.due}`)
	setTile(3, "연체", `{money.strikes}/{money.maxStrikes}`, if money.strikes > 0 then CORAL else SAGE, `{money.maxStrikes}번이면 파산!`)
	setTile(4, "오늘 손님", `약 {state.customers}명`, INK, `영업 {state.daySeconds}초`)
	local warn = pink("<b>밤마다 월세·빚 상환금과 쓴 만큼의 재료비·전기세를 내요. 남은 돈은 모두 똑같이 나눠 가져요!</b>")
	summary.Text = if d == 1
		then `말풍선 주문대로 디저트를 만들어 손님 앞에 내 주세요.\n{warn}\n처음이면 아래 {sky("<b>튜토리얼</b>")}부터!`
		else `오늘도 달콤하게!\n{warn}`
	shineRecord(false)
	startButton.Text = `DAY {d} 영업 시작`
	startButton.BackgroundColor3 = CORAL
end

-- 창이 작으면 HUD도 같이 줄인다(작은 Studio 창·휴대폰에서 화면을 가리지 않게)
local scales: { UIScale } = {}
local scaled: { GuiObject } = { bar, coins, coinGain, spendHolder, toast, side, chatMenu, recipe, holding, reopen }
for _, object in scaled do
	local s = Instance.new("UIScale")
	s.Parent = object
	table.insert(scales, s)
end

local function applyScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local size = camera.ViewportSize
	local s = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.6, 1.3)
	for _, u in scales do
		u.Scale = s
	end
	scale.Scale = math.min(1.5, (size.X - 140) / PANEL_WIDTH, (size.Y - 90) / center.Size.Y.Offset)
	local top = math.floor(60 * s)
	toast.Position = UDim2.new(0.5, 0, 0, top)
	side.Position = UDim2.new(1, -10, 0, top)
	coinGain.Position = UDim2.new(1, -math.floor(254 * s), 0, math.floor(14 * s))
	spendHolder.Position = UDim2.new(1, -math.floor(254 * s), 0, math.floor(36 * s))
	recipe.Position = UDim2.new(1, -math.floor(10 + 56 * s), 0, top)
	chatMenu.Position = UDim2.new(1, -math.floor(10 + 56 * s), 0, top + math.floor(54 * s))
end
ledgerToggle.Activated:Connect(function()
	ledgerOpen = not ledgerOpen
	renderCenter()
	applyScale() -- 창 높이가 바뀌어서 다시 맞춘다
end)
local currentCamera = workspace.CurrentCamera
if currentCamera then
	currentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
end

-- 영업을 시작할 때 화면 위에 잠깐 크게 보여 주고 스르륵 사라지는 알림: 그날 새 규칙, 그날 새 메뉴(아침 창의 새 메뉴 카드를 옮겨 쓴다)
local ANNOUNCE_SECONDS = 7 -- 카운트다운(3초)이 시작될 때부터 이만큼 보인다
local FADE_SECONDS = 1.2
local ANNOUNCE_Y = 100
local announce = Instance.new("Frame")
announce.BackgroundTransparency = 1
announce.AnchorPoint = Vector2.new(0.5, 0)
announce.Position = UDim2.new(0.5, 0, 0, ANNOUNCE_Y)
announce.Size = UDim2.fromOffset(700, 0)
announce.AutomaticSize = Enum.AutomaticSize.Y
announce.Visible = false
announce.Parent = gui
list(announce, Enum.FillDirection.Vertical, 10).HorizontalAlignment = Enum.HorizontalAlignment.Center
local announceScale = Instance.new("UIScale")
announceScale.Parent = announce
local dayRule = frame(announce, UDim2.new(1, 0, 0, 0))
dayRule.AutomaticSize = Enum.AutomaticSize.Y
dayRule.BackgroundColor3 = BABY_PINK
dayRule.LayoutOrder = 1
dayRule.Visible = false
restyle(dayRule, RIBBON_PINK, 3, 26)
local dayRulePad = Instance.new("UIPadding")
dayRulePad.PaddingLeft = UDim.new(0, 76)
dayRulePad.PaddingRight = UDim.new(0, 18)
dayRulePad.PaddingTop = UDim.new(0, 14)
dayRulePad.PaddingBottom = UDim.new(0, 14)
dayRulePad.Parent = dayRule
local dayRuleBadge = badge(dayRule, "📢", 46)
dayRuleBadge.AnchorPoint = Vector2.new(0, 0.5)
dayRuleBadge.Position = UDim2.new(0, -62, 0.5, 0)
local dayRuleText = text(dayRule, "", 18, INK)
dayRuleText.Size = UDim2.new(1, 0, 0, 0)
dayRuleText.AutomaticSize = Enum.AutomaticSize.Y
dayRuleText.TextXAlignment = Enum.TextXAlignment.Left
dayRuleText.RichText = true
local lastPhase = ""

-- 사라질 때 투명하게 만들 속성들(배경·글·그림·테두리)과 원래 값
type Faded = { object: Instance, property: string, value: number }
local function fadeTargets(root: Instance): { Faded }
	local found: { Faded } = {}
	local function record(object: Instance, property: string, value: number)
		table.insert(found, { object = object, property = property, value = value })
	end
	local function add(object: Instance)
		if object:IsA("GuiObject") then
			record(object, "BackgroundTransparency", object.BackgroundTransparency)
		end
		if object:IsA("TextLabel") then
			record(object, "TextTransparency", object.TextTransparency)
		elseif object:IsA("ViewportFrame") then
			record(object, "ImageTransparency", object.ImageTransparency)
		elseif object:IsA("UIStroke") then
			record(object, "Transparency", object.Transparency)
		end
	end
	add(root)
	for _, object in root:GetDescendants() do
		add(object)
	end
	return found
end

local announceSeq = 0
local function showAnnounce(rules: { string }, fresh: { MenuView })
	if #rules == 0 and #fresh == 0 then
		return
	end
	announceSeq += 1
	local seq = announceSeq
	dayRule.Visible = #rules > 0
	dayRuleText.Text = `<font color="#f080a0"><b>새 규칙!</b></font>  {table.concat(rules, " ")}`
	if #fresh > 0 then
		menuCard.Parent = announce
		menuCard.LayoutOrder = 2
		menuCard.Visible = true
		showMenuCard(fresh, "🍨 오늘의 새 메뉴!")
	end
	-- 위에서 통! 하고 내려온다
	announce.Position = UDim2.new(0.5, 0, 0, ANNOUNCE_Y - 60)
	announce.Visible = true
	TweenService:Create(announce, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, ANNOUNCE_Y) }):Play()
	task.delay(ANNOUNCE_SECONDS, function()
		if seq ~= announceSeq then
			return
		end
		-- 스르륵: 조금 떠오르며 투명해진 뒤 숨기고, 다음에 다시 보이도록 투명도를 되돌린다
		local info = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local targets = fadeTargets(announce)
		for _, item in targets do
			TweenService:Create(item.object, info, { [item.property] = 1 }):Play()
		end
		TweenService:Create(announce, info, { Position = UDim2.new(0.5, 0, 0, ANNOUNCE_Y - 24) }):Play()
		task.delay(FADE_SECONDS, function()
			if seq == announceSeq then
				announce.Visible = false
				dayRule.Visible = false
				if menuCard.Parent == announce then
					menuCard.Visible = false
					menuCard.Parent = center
				end
			end
			for _, item in targets do
				(item.object :: any)[item.property] = item.value
			end
		end)
	end)
end

-- 오른쪽 위 코인: 바뀐 만큼 숫자가 올라가거나 내려간다(오르면 코인이 톡 튀고 "+N"이 떴다 사라진다)
local holdCoinsUntil = 0 -- 날아가는 코인이 지갑에 닿을 때까지(Earned)
local coinsPending = false
local function updateCoins()
	local amount = liveCoins()
	local before = shownWallet
	debtLabel.Text = if state.debt > 0 then `빚 {state.debt}` else "빚 없음"
	local wait = holdCoinsUntil - os.clock()
	if before ~= nil and amount > before and wait > 0 then
		if not coinsPending then
			coinsPending = true
			task.delay(wait, function()
				coinsPending = false
				updateCoins()
			end)
		end
		return
	end
	if before ~= nil and amount < before and state.phase == "open" then
		showSpend(before - amount)
	end
	if before == nil then
		coinValue.Value = amount
	elseif amount ~= before then
		local rising = amount > before
		TweenService:Create(coinValue, TweenInfo.new(if rising then 0.6 else 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = amount }):Play()
		if rising then
			coinPop.Scale = 1.5
			TweenService:Create(coinPop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			coinGain.Text = `+{amount - before}`
			coinGain.Visible = true
			coinGain.TextTransparency = 0
			TweenService:Create(coinGain, TweenInfo.new(1.2), { TextTransparency = 1 }):Play()
		end
	end
	coinLabel.TextColor3 = if amount < 0 then CORAL else GOLD_TEXT
	shownWallet = amount
end

-- 흔들흔들(연체·파산 경고): 좌우로 몇 번 기울었다 돌아온다
local function shake(object: GuiObject)
	task.spawn(function()
		for _, angle in { 6, -6, 5, -5, 3, -3, 0 } do
			object.Rotation = angle
			task.wait(0.045)
		end
	end)
end

-- 정산 숫자 카드가 하나씩 톡톡. 연체·파산이면 남은 빚 카드와 제목이 흔들린다.
local function popTiles()
	for i, tile in tiles do
		tile.pop.Scale = 0.2
		TweenService:Create(tile.pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.08 + (i - 1) * 0.09), { Scale = 1 }):Play()
	end
	local r = state.report
	if r and (r.short > 0 or r.bankrupt) then
		task.delay(0.6, function()
			shake(tiles[4].box)
			shake(heading)
		end)
	end
end

-- 가운데 창: 보일 때 말랑 팝(크기는 applyScale 뒤에 popPanel이 맞춘다), 숨길 때 쏙
local panelPopPending = false
local function showPanel()
	local inMenu = state.phase == "morning" or state.phase == "night"
	local want = inMenu and not panelHidden and not introPlaying
	if want and (not center.Visible or UiDeco.isClosing(scale)) then
		center.Visible = true
		panelPopPending = true
	elseif not want and center.Visible and not UiDeco.isClosing(scale) then
		UiDeco.popOut(scale, function()
			center.Visible = false
		end)
	end
	reopen.Visible = inMenu and panelHidden and not introPlaying
end

local function popPanel()
	if not panelPopPending then
		return
	end
	panelPopPending = false
	UiDeco.popIn(scale, scale.Scale)
	if state.phase == "night" and state.report then
		popTiles()
	end
end

browseButton.Activated:Connect(function()
	panelHidden = true
	showPanel()
end)
reopen.Activated:Connect(function()
	panelHidden = false
	showPanel()
	applyScale()
	popPanel()
end)

local function stopIntro()
	introSeq += 1
	introPlaying = false
	earnedShow.Visible = false
end

-- 영업 끝 → "오늘 번 돈"이 0부터 올라가고 → 정산 창. 오른쪽 위 코인(월세 등이 빠진 지갑)도 정산 창과 같이 바뀐다.
local function playIntro(earned: number)
	introSeq += 1
	local seq = introSeq
	introPlaying = true
	showPanel()
	earnedShow.Visible = true
	earnedPop.Scale = 0.3
	TweenService:Create(earnedPop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	earnedValue.Value = 0
	earnedNumber.Text = "+0"
	numberPop.Scale = 1
	local countTime = 1.5
	TweenService:Create(earnedValue, TweenInfo.new(countTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.3), { Value = earned }):Play()
	bigCoin.Size = UDim2.fromScale(1, 1)
	TweenService:Create(bigCoin, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 4, true, 0.3), { Size = UDim2.fromScale(0.08, 1) }):Play()
	task.delay(0.3 + countTime, function()
		if seq == introSeq then
			numberPop.Scale = 1.3
			TweenService:Create(numberPop, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end)
	local total = Config.NightIntroSeconds
	task.delay(total - 0.25, function()
		if seq == introSeq then
			TweenService:Create(earnedPop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		end
	end)
	task.delay(total, function()
		if seq ~= introSeq then
			return
		end
		stopIntro()
		updateCoins()
		if state.phase == "night" and state.report then
			renderCenter()
		end
		showPanel()
		applyScale()
		popPanel()
	end)
end

-- ── 날짜가 바뀔 때: 분홍 땡땡이 커튼이 왼쪽에서 쓱 들어와 "DAY N"을 보여 주고 오른쪽으로 빠진다 ──
local curtain = Instance.new("Frame")
curtain.Size = UDim2.fromScale(1, 1)
curtain.Position = UDim2.fromScale(-1, 0)
curtain.BackgroundColor3 = Color3.fromRGB(248, 214, 226)
curtain.BorderSizePixel = 0
curtain.ZIndex = 30
curtain.Visible = false
curtain.Parent = gui
for row = 0, 7 do
	for col = 0, 11 do
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale((col + (if row % 2 == 0 then 0.25 else 0.75)) / 12, (row + 0.5) / 8)
		dot.Size = UDim2.fromOffset(22, 22)
		dot.BackgroundColor3 = WHITE
		dot.BackgroundTransparency = 0.35
		dot.BorderSizePixel = 0
		dot.ZIndex = 30
		corner(dot, 11)
		dot.Parent = curtain
	end
end
local curtainDay = text(curtain, "", 96, WHITE, ROUND)
curtainDay.AnchorPoint = Vector2.new(0.5, 0.5)
curtainDay.Position = UDim2.fromScale(0.5, 0.44)
curtainDay.Size = UDim2.fromOffset(600, 120)
curtainDay.ZIndex = 31
local curtainStroke = Instance.new("UIStroke")
curtainStroke.Color = Color3.fromRGB(236, 120, 150)
curtainStroke.Thickness = 5
curtainStroke.Parent = curtainDay
local curtainSub = text(curtain, "오늘도 달콤하게! 🍓", 28, Color3.fromRGB(200, 90, 120), ROUND)
curtainSub.AnchorPoint = Vector2.new(0.5, 0.5)
curtainSub.Position = UDim2.fromScale(0.5, 0.56)
curtainSub.Size = UDim2.fromOffset(600, 40)
curtainSub.ZIndex = 31
local curtainSeq = 0
local lastDay = 0

local function playCurtain(day: number)
	curtainSeq += 1
	local seq = curtainSeq
	curtainDay.Text = `DAY {day}`
	curtain.Position = UDim2.fromScale(-1, 0)
	curtain.Visible = true
	TweenService:Create(curtain, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0) }):Play()
	task.delay(0.8, function()
		if seq ~= curtainSeq then
			return
		end
		TweenService:Create(curtain, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(1, 0) }):Play()
		task.delay(0.35, function()
			if seq == curtainSeq then
				curtain.Visible = false
			end
		end)
	end)
end

local function applyState(incoming: State)
	state = incoming
	local phase = state.phase
	local previous = lastPhase
	if phase == "countdown" and previous ~= "countdown" then
		showAnnounce(state.rules, freshMenus())
	end
	lastPhase = phase
	local inMenu = phase == "morning" or phase == "night"
	if not inMenu then
		panelHidden = false
	end
	if phase == "night" and previous == "open" and state.report then
		playIntro(state.report.earned)
	elseif phase ~= "night" and introPlaying then
		stopIntro()
	end
	showPanel()
	local tutorial = phase == "tutorial"
	bar.Visible = phase == "open" or phase == "countdown" or tutorial
	-- 3·2·1은 RenderStepped가 숫자가 바뀔 때마다 띄운다(showCount)
	if phase == "open" and previous == "countdown" then
		showOpen()
	elseif phase ~= "open" and phase ~= "countdown" then
		hideCount()
	end
	dayChip.Text = if tutorial then "연습" else `DAY {state.day}`
	if tutorial then
		timeLabel.Text = ""
	end
	-- 정산 창이 뜨기 전("오늘 번 돈"이 올라가는 동안)에는 오른쪽 위 코인을 그대로 둔다
	if not introPlaying then
		updateCoins()
	end
	if inMenu then
		renderCenter()
	end
	renderRecipe()
	applyScale()
	popPanel()
	announceScale.Scale = scales[1].Scale -- 위 바와 같은 크기로
	updateAdmin()
	-- 날짜가 바뀌면(다음 날 시작·파산 뒤 처음부터) 분홍 커튼이 쓱 지나간다
	if lastDay ~= 0 and state.day ~= lastDay and (phase == "countdown" or phase == "morning") then
		playCurtain(state.day)
	end
	lastDay = state.day
end

local function clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

RunService.RenderStepped:Connect(function()
	local t = workspace:GetServerTimeNow()
	if state.phase == "open" then
		timeLabel.Text = clock(state.endsAt - t)
	elseif state.phase == "countdown" then
		timeLabel.Text = clock(state.daySeconds)
		showCount(math.max(1, math.ceil(state.endsAt - t)))
	elseif state.phase == "night" and state.report then
		updateNightButton()
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		toggleRecipe()
	else
		local keys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
		local index = table.find(keys, input.KeyCode)
		if index then
			say(index)
		end
	end
end)

local toastSeq = 0
toastEvent.OnClientEvent:Connect(function(message: string)
	toastSeq += 1
	local seq = toastSeq
	toast.Text = message
	toast.Visible = true
	task.delay(2.4, function()
		if seq == toastSeq then
			toast.Visible = false
		end
	end)
end)

stateEvent.OnClientEvent:Connect(function(incoming: State)
	applyState(incoming)
end)

-- ── 서빙하면 코인이 손님 자리에서 오른쪽 위 지갑으로 날아간다. 팀 콤보·단체 보너스면 색종이도 펑! ──
local CONFETTI = {
	Color3.fromRGB(255, 170, 200),
	Color3.fromRGB(150, 210, 245),
	Color3.fromRGB(255, 220, 120),
	Color3.fromRGB(170, 225, 190),
	Color3.fromRGB(205, 180, 245),
}

-- 이 화면(IgnoreGuiInset)의 좌표: 월드 위치는 그대로, AbsolutePosition은 위쪽 메뉴 바 높이만큼 더한다
local function screenPoint(world: Vector3): Vector2
	local camera = workspace.CurrentCamera
	if camera then
		local p = camera:WorldToViewportPoint(world)
		if p.Z > 0 then
			return Vector2.new(p.X, p.Y)
		end
		return Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y * 0.7)
	end
	return Vector2.new(400, 400)
end

local function walletPoint(): Vector2
	return coinIcon.AbsolutePosition + coinIcon.AbsoluteSize / 2 + GuiService:GetGuiInset()
end

local function flyCoins(from: Vector2, amount: number)
	local count = math.clamp(math.floor(amount / 6) + 2, 3, 8)
	for i = 1, count do
		local coin = Instance.new("Frame")
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		coin.Size = UDim2.fromOffset(24, 24)
		coin.Position = UDim2.fromOffset(from.X, from.Y)
		coin.BackgroundColor3 = GOLD
		coin.BorderSizePixel = 0
		coin.ZIndex = 20
		corner(coin, 12)
		local edge = Instance.new("UIStroke")
		edge.Color = Color3.fromRGB(255, 226, 150)
		edge.Thickness = 3
		edge.Parent = coin
		coin.Parent = gui
		-- 톡 흩어졌다가
		local angle = math.random() * math.pi * 2
		local spread = from + Vector2.new(math.cos(angle), math.sin(angle)) * (30 + math.random() * 45)
		TweenService:Create(coin, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(spread.X, spread.Y) }):Play()
		-- 하나씩 지갑으로 쏙
		task.delay(0.25 + i * 0.05, function()
			local target = walletPoint()
			local fly = TweenService:Create(coin, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(target.X, target.Y),
				Size = UDim2.fromOffset(14, 14),
			})
			fly.Completed:Once(function()
				coin:Destroy()
				coinPop.Scale = 1.35
				TweenService:Create(coinPop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end)
			fly:Play()
		end)
	end
end

local function confetti(from: Vector2)
	for _ = 1, 28 do
		local piece = Instance.new("Frame")
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Size = UDim2.fromOffset(math.random(8, 14), math.random(5, 9))
		piece.Position = UDim2.fromOffset(from.X, from.Y)
		piece.BackgroundColor3 = CONFETTI[math.random(1, #CONFETTI)]
		piece.BorderSizePixel = 0
		piece.Rotation = math.random(0, 360)
		piece.ZIndex = 19
		corner(piece, 3)
		piece.Parent = gui
		-- 위로 부채꼴로 펑 → 팔랑팔랑 떨어지며 사라짐
		local angle = -math.pi / 2 + (math.random() - 0.5) * 2.4
		local peak = from + Vector2.new(math.cos(angle), math.sin(angle)) * (110 + math.random() * 150)
		TweenService:Create(piece, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(peak.X, peak.Y),
			Rotation = piece.Rotation + math.random(-180, 180),
		}):Play()
		task.delay(0.45, function()
			TweenService:Create(piece, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(peak.X + (math.random() - 0.5) * 80, peak.Y + 170),
				Rotation = piece.Rotation + math.random(-360, 360),
				BackgroundTransparency = 1,
			}):Play()
			task.delay(0.95, function()
				piece:Destroy()
			end)
		end)
	end
end

earnedEvent.OnClientEvent:Connect(function(position: Vector3, amount: number, _combo: number, _serverId: number?, big: boolean?)
	local from = screenPoint(position)
	-- 오른쪽 위 숫자는 코인이 닿을 즈음 오른다(Main이 Earned를 금고보다 먼저 보낸다)
	holdCoinsUntil = os.clock() + 0.8
	flyCoins(from, amount)
	if big then
		confetti(from)
	end
end)
readyEvent:FireServer()
