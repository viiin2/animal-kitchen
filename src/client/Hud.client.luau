--!strict
-- 화면(HUD). 영업 중에는 화면을 가리지 않게 맨 위 가운데 작은 바와 오른쪽 작은 버튼만 둔다.
--   맨 위 바: DAY · 남은 시간 · 가게 금고/지출/밤에 낼 돈(손님 말풍선과 겹치지 않게 화면 맨 위에 붙인다)
--   오른쪽 위: 내 지갑(밤 정산에서 순수익을 나눠 받는다)과 남은 빚
--   오른쪽 버튼: 레시피북(R, 켜고 끄기) · 말풍선(1~4) · 카메라(C) · 끼었어요(처음 자리로)
--   아침·밤: 가운데 창(아침: 오늘 낼 돈·메뉴, 밤: 정산 장부·나눠 가진 돈·빚). 아래 버튼으로 상점 창(Shop)·동물 고르기 창(AnimalPicker)·튜토리얼을 연다.
--   밤에는 Config.NightSeconds 뒤 저절로 다음 날이 시작되고, 모두 준비를 누르면 바로 시작된다.
--   "가게 둘러보기"로 접을 수 있다.
-- 주문은 손님 머리 위 말풍선(Bubbles)이 보여 준다. 판정은 모두 서버가 한다.
local Players = game:GetService("Players")
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

type MenuView = { dish: string, name: string, steps: string, price: number, isNew: boolean }
type Today = { sales: number, tips: number, served: number, missed: number }
type AnimalView = { name: string, price: number, owned: boolean }
type Person = { userId: number, name: string, wallet: number, best: number }
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

-- 오늘 밤 낼 돈(지금까지 쓴 운영비까지)
local function nightBill(): number
	local money = state.money
	return money.spent + money.rent + money.due + money.basePower
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

-- ── 맨 위 바: DAY · 남은 시간 · 금고 · 지출 · 밤에 낼 돈(막대는 금고가 낼 돈을 얼마나 채웠는지) ──

local bar = frame(gui, UDim2.fromOffset(570, 52))
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.new(0.5, 0, 0, 4)
bar.Visible = false
local dayChip = text(bar, "DAY 1", 23, CORAL, ROUND)
dayChip.Size = UDim2.fromOffset(92, 52)
local timeLabel = text(bar, "3:00", 23, INK, ROUND)
timeLabel.Size = UDim2.fromOffset(76, 52)
timeLabel.Position = UDim2.fromOffset(88, 0)
local salesLabel = text(bar, "", 17, INK)
salesLabel.Size = UDim2.fromOffset(390, 24)
salesLabel.Position = UDim2.fromOffset(170, 4)
salesLabel.TextXAlignment = Enum.TextXAlignment.Left
local progressBack = Instance.new("Frame")
progressBack.BackgroundColor3 = Color3.fromRGB(240, 230, 218)
progressBack.BorderSizePixel = 0
progressBack.Size = UDim2.fromOffset(390, 12)
progressBack.Position = UDim2.fromOffset(170, 32)
corner(progressBack, 5)
progressBack.Parent = bar
local progressFill = Instance.new("Frame")
progressFill.BackgroundColor3 = SAGE
progressFill.BorderSizePixel = 0
progressFill.Size = UDim2.fromScale(0, 1)
corner(progressFill, 5)
progressFill.Parent = progressBack

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
local coinLabel = text(coins, "0", 24, Color3.fromRGB(196, 140, 48), ROUND)
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
-- 숫자가 띠롱띠롱 올라가게: 표시하는 값은 NumberValue를 트윈한다
local coinValue = Instance.new("NumberValue")
coinValue:GetPropertyChangedSignal("Value"):Connect(function()
	coinLabel.Text = tostring(math.floor(coinValue.Value + 0.5))
end)
local coinPop = Instance.new("UIScale")
coinPop.Parent = coinIcon
local salesValue = Instance.new("NumberValue")

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
local function updateAdmin()
	local admin = player:GetAttribute("Admin") == true
	local playing = state.phase == "open" or state.phase == "countdown" or state.phase == "tutorial"
	adminButton.Visible = admin
	stopButton.Visible = admin and playing
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
	recipe.Visible = not recipe.Visible
	if recipe.Visible then
		chatMenu.Visible = false
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
local NIGHT_HEIGHT = 640 -- 밤에는 정산 장부가 들어가서 더 길다(넘치면 장부가 스크롤된다)
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

-- 새 규칙 카드: 그날 새로 생기는 규칙(글 한 줄로는 눈에 잘 안 띄었다)
local RULE_CARD_HEIGHT = 100
local ruleCard = frame(center, UDim2.new(1, 0, 0, RULE_CARD_HEIGHT))
ruleCard.Position = UDim2.fromOffset(0, TOP)
ruleCard.BackgroundColor3 = Color3.fromRGB(255, 234, 222)
ruleCard.Visible = false
local ruleBorder = ruleCard:FindFirstChildOfClass("UIStroke")
if ruleBorder then
	ruleBorder.Color = CORAL
	ruleBorder.Thickness = 3
end
local ruleIcon = text(ruleCard, "📢", 32, CORAL)
ruleIcon.Position = UDim2.fromOffset(8, 0)
ruleIcon.Size = UDim2.fromOffset(48, RULE_CARD_HEIGHT)
local ruleTitle = text(ruleCard, "새 규칙!", 21, CORAL, ROUND)
ruleTitle.Position = UDim2.fromOffset(60, 8)
ruleTitle.Size = UDim2.new(1, -70, 0, 26)
ruleTitle.TextXAlignment = Enum.TextXAlignment.Left
local ruleBody = text(ruleCard, "", 18, INK)
ruleBody.Position = UDim2.fromOffset(60, 36)
ruleBody.Size = UDim2.new(1, -70, 0, 58)
ruleBody.TextXAlignment = Enum.TextXAlignment.Left
ruleBody.TextYAlignment = Enum.TextYAlignment.Top

-- 숫자 카드. 아침: 낼 돈 · 빚 · 연체 · 손님, 밤: 매출 · 낸 돈 · 순수익 · 남은 빚. 글 몇 줄로는 작고 잘 안 보였다.
type Tile = { box: Frame, label: TextLabel, value: TextLabel, sub: TextLabel }
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
	table.insert(tiles, { box = box, label = label, value = value, sub = sub })
end

-- 새 메뉴 카드: 오늘(아침)·내일(밤 정산)의 새 메뉴를 그림·이름·값·만드는 순서로 크게 보여 준다
local MENU_CARD_HEIGHT = 112
local menuCard = frame(center, UDim2.new(1, 0, 0, MENU_CARD_HEIGHT))
menuCard.BackgroundColor3 = Color3.fromRGB(232, 245, 253)
menuCard.Visible = false
local menuBorder = menuCard:FindFirstChildOfClass("UIStroke")
if menuBorder then
	menuBorder.Color = Color3.fromRGB(150, 202, 238)
	menuBorder.Thickness = 3
end
local menuView = Instance.new("ViewportFrame")
menuView.BackgroundColor3 = WHITE
menuView.Position = UDim2.fromOffset(12, 11)
menuView.Size = UDim2.fromOffset(90, 90)
menuView.Ambient = Color3.fromRGB(200, 190, 196)
menuView.LightColor = Color3.fromRGB(255, 246, 250)
menuView.LightDirection = Vector3.new(-1, -2, -1)
corner(menuView, 45)
menuView.Parent = menuCard
local menuTitle = text(menuCard, "", 20, Color3.fromRGB(70, 140, 200), ROUND)
menuTitle.Position = UDim2.fromOffset(116, 8)
menuTitle.Size = UDim2.new(1, -126, 0, 24)
menuTitle.TextXAlignment = Enum.TextXAlignment.Left
local menuName = text(menuCard, "", 23, INK)
menuName.Position = UDim2.fromOffset(116, 34)
menuName.Size = UDim2.new(1, -126, 0, 30)
menuName.TextXAlignment = Enum.TextXAlignment.Left
menuName.RichText = true
local menuSteps = text(menuCard, "", 18, INK)
menuSteps.Position = UDim2.fromOffset(116, 68)
menuSteps.Size = UDim2.new(1, -126, 0, 36)
menuSteps.TextXAlignment = Enum.TextXAlignment.Left
menuSteps.TextYAlignment = Enum.TextYAlignment.Top
local shownDish = ""

-- 아이스크림은 맛이 정해져 있지 않아서 보기 좋은 한 가지로 그린다
local SAMPLE_ICE: Config.IceSpec = { base = "cone", flavors = { "strawberry", "vanilla" }, topping = "sprinkles" }

local function showMenuCard(menus: { MenuView }, title: string)
	local first = menus[1]
	menuTitle.Text = title
	local names = {}
	for _, menu in menus do
		table.insert(names, `<b>{menu.name}</b>  <font color="#c48c30">{menu.price}코인</font>`)
	end
	menuName.Text = table.concat(names, "   ·   ")
	menuSteps.Text = first.steps
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
-- 밤 정산 장부: 왼쪽 들어온 돈·나눠 가진 돈, 오른쪽 나간 돈·빚
local ledger = Instance.new("Frame")
ledger.BackgroundTransparency = 1
ledger.Size = UDim2.new(1, -12, 0, 0)
ledger.AutomaticSize = Enum.AutomaticSize.Y
ledger.LayoutOrder = 1
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
browseButton.Activated:Connect(function()
	panelHidden = true
	center.Visible = false
	reopen.Visible = true
end)
reopen.Activated:Connect(function()
	panelHidden = false
	center.Visible = true
	reopen.Visible = false
end)

local countdown = text(gui, "", 110, WHITE, ROUND)
countdown.AnchorPoint = Vector2.new(0.5, 0.5)
countdown.Position = UDim2.fromScale(0.5, 0.45)
countdown.Size = UDim2.fromOffset(240, 140)
countdown.TextStrokeTransparency = 0.5
countdown.TextStrokeColor3 = INK
countdown.Visible = false

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
		startButton.Text = if mine then "준비 완료!" else "DAY 1 아침으로"
		readyLabel.Text = `{left}초 뒤 처음부터 · 준비 {#state.ready}/{total}`
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
	setTile(1, "오늘 매출", `+{r.earned}`, GOLD, `손님 {today.served}명 · 돌아간 {today.missed}명`)
	setTile(2, "오늘 낸 돈", `-{r.bill}`, CORAL, `운영비 {r.operating} · 월세·상환 {r.bill - r.operating}`)
	local mine = myShare(r)
	local mineText = if not mine then "" elseif r.profit >= 0 then `내 몫 +{mine.change}` else `내가 메운 돈 {-mine.change}`
	setTile(3, "순수익", signed(r.profit), if r.profit >= 0 then SAGE else CORAL, mineText)
	setTile(4, "남은 빚", if r.bankrupt then "파산" else tostring(r.debt), if r.strikes > 0 then CORAL else INK, if r.strikes > 0 then `연체 {r.strikes}/{maxStrikes}` else "연체 없음")

	local count = #r.shares
	local result: string
	if r.bankrupt then
		result = `{pink(`<b>연체가 {maxStrikes}번 쌓여 가게가 문을 닫았어요.</b>`)}\n빚 {Config.Debt.start}을 다시 지고 DAY 1 아침부터 다시 시작해요. 지갑과 상점 업그레이드도 처음으로 돌아가요.`
	elseif r.short > 0 then
		result = `{pink(`<b>지갑으로 메우고도 {r.short} 모자라서 빚에 더했어요</b> (연체료 +{r.lateFee})`)}\n연체 {r.strikes}/{maxStrikes} · {maxStrikes}번이면 파산해요!`
	elseif r.profit < 0 then
		result = `적자 {-r.profit}을(를) {if count > 1 then `{count}명이 1/n씩` else "내 지갑에서"} 메웠어요.`
	elseif count > 1 then
		result = `순수익 {r.profit}을(를) {count}명이 똑같이 나눠 가졌어요.`
	else
		result = `순수익 {r.profit}이(가) 내 지갑에 들어왔어요.`
	end
	-- 최고 기록: 새로 세웠으면 크게, 파산했으면 이번에 며칠 버텼는지
	local mineNow = me()
	local record = ""
	if table.find(r.newRecords, player.UserId) then
		record = `{sky(`<b>🏆 신기록! DAY {r.survived}까지 버텼어요!</b>`)}\n`
	elseif r.bankrupt and r.survived > 0 then
		record = `이번 가게는 <b>DAY {r.survived}</b>까지 버텼어요. (최고 기록 DAY {if mineNow then mineNow.best else r.survived})\n`
	end
	summary.Text = record .. result

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
	center.Size = UDim2.fromOffset(PANEL_WIDTH, if night then NIGHT_HEIGHT else PANEL_HEIGHT)
	-- 새 규칙·새 메뉴 카드는 아침에만. 밤에는 장부 자리가 좁아서 빼고, 영업을 시작할 때 화면 위에 잠깐 보여 준다(showAnnounce).
	local hasRules = #state.rules > 0 and not night
	-- 위에서부터: 숫자 카드 → (아침) 새 규칙 카드 → 새 메뉴 카드 → 글·장부
	local y = TOP + TILE_HEIGHT + 10
	stats.Visible = true
	ledger.Visible = night
	readyLabel.Visible = night
	local mine = me()
	recordLabel.Text = if mine and mine.best > 0 then `🏆 최고 기록 DAY {mine.best}` else "🏆 첫 도전!"
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
		renderNight(report)
		return
	end
	-- 아침: 숫자 카드와 짧은 안내만(메뉴 조합·키 설명은 레시피북 R에 있다)
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
	startButton.Text = `DAY {d} 영업 시작`
	startButton.BackgroundColor3 = CORAL
end

-- 창이 작으면 HUD도 같이 줄인다(작은 Studio 창·휴대폰에서 화면을 가리지 않게)
local scales: { UIScale } = {}
local scaled: { GuiObject } = { bar, coins, coinGain, toast, side, chatMenu, recipe, holding, reopen }
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
	recipe.Position = UDim2.new(1, -math.floor(10 + 56 * s), 0, top)
	chatMenu.Position = UDim2.new(1, -math.floor(10 + 56 * s), 0, top + math.floor(54 * s))
end
local currentCamera = workspace.CurrentCamera
if currentCamera then
	currentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
end

local function salesText()
	salesLabel.Text = `금고 {math.floor(salesValue.Value + 0.5)} · 지출 {state.money.spent} · 밤에 낼 돈 {nightBill()}`
end
salesValue:GetPropertyChangedSignal("Value"):Connect(salesText)

-- 영업을 시작할 때 화면 위에 잠깐 크게 보여 주고 스르륵 사라지는 알림: 그날 새 규칙, 그날 새 메뉴(아침 창의 새 메뉴 카드를 옮겨 쓴다)
local ANNOUNCE_SECONDS = 7 -- 카운트다운(3초)이 시작될 때부터 이만큼 보인다
local FADE_SECONDS = 1.2
local ANNOUNCE_Y = 100
local announce = Instance.new("Frame")
announce.BackgroundTransparency = 1
announce.AnchorPoint = Vector2.new(0.5, 0)
announce.Position = UDim2.new(0.5, 0, 0, ANNOUNCE_Y)
announce.Size = UDim2.fromOffset(640, 0)
announce.AutomaticSize = Enum.AutomaticSize.Y
announce.Visible = false
announce.Parent = gui
list(announce, Enum.FillDirection.Vertical, 10).HorizontalAlignment = Enum.HorizontalAlignment.Center
local announceScale = Instance.new("UIScale")
announceScale.Parent = announce
local dayRule = frame(announce, UDim2.new(1, 0, 0, 0))
dayRule.AutomaticSize = Enum.AutomaticSize.Y
dayRule.BackgroundColor3 = Color3.fromRGB(255, 234, 222)
dayRule.LayoutOrder = 1
dayRule.Visible = false
pad(dayRule, 16, 12)
local dayRuleText = text(dayRule, "", 18, INK)
dayRuleText.Size = UDim2.new(1, 0, 0, 0)
dayRuleText.AutomaticSize = Enum.AutomaticSize.Y
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
	dayRuleText.Text = `<font color="#ec8464"><b>📢 새 규칙!</b></font>  {table.concat(rules, " ")}`
	if #fresh > 0 then
		menuCard.Parent = announce
		menuCard.LayoutOrder = 2
		menuCard.Visible = true
		showMenuCard(fresh, "🍨 오늘의 새 메뉴!")
	end
	announce.Position = UDim2.new(0.5, 0, 0, ANNOUNCE_Y)
	announce.Visible = true
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

local function applyState(incoming: State)
	state = incoming
	local phase = state.phase
	if phase == "countdown" and lastPhase ~= "countdown" then
		showAnnounce(state.rules, freshMenus())
	end
	lastPhase = phase
	local inMenu = phase == "morning" or phase == "night"
	if not inMenu then
		panelHidden = false
	end
	center.Visible = inMenu and not panelHidden
	reopen.Visible = inMenu and panelHidden
	local tutorial = phase == "tutorial"
	bar.Visible = phase == "open" or phase == "countdown" or tutorial
	countdown.Visible = phase == "countdown"
	dayChip.Text = if tutorial then "연습" else `DAY {state.day}`
	if tutorial then
		salesLabel.Text = "튜토리얼 중 (코인 없음)"
	elseif state.till < salesValue.Value then
		salesValue.Value = state.till -- 새 날: 바로 줄인다
		salesText()
	else
		TweenService:Create(salesValue, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = state.till }):Play()
		salesText()
	end
	progressBack.Visible = not tutorial
	if tutorial then
		timeLabel.Text = ""
	end
	local wallet = myWallet()
	local before = shownWallet
	if before == nil then
		coinValue.Value = wallet
	else
		local rising = wallet > before
		TweenService:Create(coinValue, TweenInfo.new(if rising then 0.7 else 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = wallet }):Play()
		if rising then
			coinPop.Scale = 1.5
			TweenService:Create(coinPop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	debtLabel.Text = if state.debt > 0 then `빚 {state.debt}` else "빚 없음"
	if before and wallet > before then
		coinGain.Text = `+{wallet - before}`
		coinGain.Visible = true
		coinGain.TextTransparency = 0
		local fade = TweenService:Create(coinGain, TweenInfo.new(1.2), { TextTransparency = 1 })
		fade:Play()
	end
	shownWallet = wallet
	-- 막대: 금고가 오늘 밤 낼 돈을 얼마나 채웠는지(다 채우면 초록, 아직이면 주황)
	local bill = nightBill()
	progressFill.BackgroundColor3 = if state.till >= bill then SAGE else CORAL
	TweenService:Create(progressFill, TweenInfo.new(0.5), { Size = UDim2.fromScale(math.clamp(state.till / math.max(bill, 1), 0, 1), 1) }):Play()
	if inMenu then
		renderCenter()
	end
	renderRecipe()
	applyScale()
	announceScale.Scale = scales[1].Scale -- 위 바와 같은 크기로
	updateAdmin()
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
		countdown.Text = tostring(math.max(1, math.ceil(state.endsAt - t)))
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
readyEvent:FireServer()
