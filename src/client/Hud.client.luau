--!strict
-- 화면(HUD). 영업 중에는 화면을 가리지 않게 맨 위 가운데 작은 바와 오른쪽 작은 버튼만 둔다.
--   맨 위 바: DAY · 남은 시간 · 오늘 매출/목표(손님 말풍선과 겹치지 않게 화면 맨 위에 붙인다)
--   오른쪽 위: 코인(모두의 지갑, 판 만큼 바로 늘어난다)
--   오른쪽 버튼: 레시피북(R, 켜고 끄기) · 말풍선(1~4) · 카메라(C) · 끼었어요(처음 자리로)
--   오른쪽 위: 코인과 남은 빚
--   아침·밤: 가운데 창(정산·새 메뉴·빚). 아래 버튼으로 상점 창(Shop)·동물 고르기 창(AnimalPicker)·튜토리얼을 연다.
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
type Today = { sales: number, tips: number, served: number, missed: number, refunded: number }
type AnimalView = { name: string, price: number, owned: boolean }
type State = {
	phase: string,
	day: number,
	upcomingDay: number,
	endsAt: number,
	daySeconds: number,
	target: number,
	wallet: number,
	today: Today,
	passed: boolean,
	menus: { MenuView },
	animals: { AnimalView },
	rules: { string },
	debt: number,
	debtNight: { interest: number },
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
	target = 0,
	wallet = 0,
	today = { sales = 0, tips = 0, served = 0, missed = 0, refunded = 0 },
	passed = false,
	menus = {},
	animals = {},
	rules = {},
	debt = 0,
	debtNight = { interest = 0 },
}

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

-- ── 맨 위 바: DAY · 남은 시간 · 매출 ──

local bar = frame(gui, UDim2.fromOffset(430, 46))
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.new(0.5, 0, 0, 4)
bar.Visible = false
local dayChip = text(bar, "DAY 1", 20, CORAL, ROUND)
dayChip.Size = UDim2.fromOffset(84, 46)
local timeLabel = text(bar, "3:00", 20, INK, ROUND)
timeLabel.Size = UDim2.fromOffset(70, 46)
timeLabel.Position = UDim2.fromOffset(80, 0)
local salesLabel = text(bar, "", 14, MUTED)
salesLabel.Size = UDim2.fromOffset(250, 20)
salesLabel.Position = UDim2.fromOffset(160, 5)
salesLabel.TextXAlignment = Enum.TextXAlignment.Left
local progressBack = Instance.new("Frame")
progressBack.BackgroundColor3 = Color3.fromRGB(240, 230, 218)
progressBack.BorderSizePixel = 0
progressBack.Size = UDim2.fromOffset(250, 10)
progressBack.Position = UDim2.fromOffset(160, 28)
corner(progressBack, 5)
progressBack.Parent = bar
local progressFill = Instance.new("Frame")
progressFill.BackgroundColor3 = SAGE
progressFill.BorderSizePixel = 0
progressFill.Size = UDim2.fromScale(0, 1)
corner(progressFill, 5)
progressFill.Parent = progressBack

-- ── 오른쪽 위: 코인 ──

local coins = frame(gui, UDim2.fromOffset(196, 40))
coins.AnchorPoint = Vector2.new(1, 0)
coins.Position = UDim2.new(1, -10, 0, 4)
local coinIcon = Instance.new("Frame")
coinIcon.Size = UDim2.fromOffset(26, 26)
coinIcon.Position = UDim2.fromOffset(9, 7)
coinIcon.BackgroundColor3 = GOLD
coinIcon.BorderSizePixel = 0
corner(coinIcon, 13)
coinIcon.Parent = coins
local coinMark = Instance.new("UIStroke")
coinMark.Color = Color3.fromRGB(255, 226, 150)
coinMark.Thickness = 3
coinMark.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
coinMark.Parent = coinIcon
local coinLabel = text(coins, "0", 20, Color3.fromRGB(196, 140, 48), ROUND)
coinLabel.Position = UDim2.fromOffset(42, 0)
coinLabel.Size = UDim2.fromOffset(70, 40)
coinLabel.TextXAlignment = Enum.TextXAlignment.Left
local debtLabel = text(coins, "", 13, MUTED)
debtLabel.Position = UDim2.fromOffset(112, 0)
debtLabel.Size = UDim2.fromOffset(76, 40)
debtLabel.TextXAlignment = Enum.TextXAlignment.Right
-- 코인이 들어오면 "+12"가 떠올랐다 사라진다
local coinGain = text(gui, "", 18, Color3.fromRGB(196, 140, 48), ROUND)
coinGain.AnchorPoint = Vector2.new(1, 0)
coinGain.Size = UDim2.fromOffset(120, 24)
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

local toast = text(gui, "", 16, WHITE)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 60)
toast.Size = UDim2.fromOffset(460, 34)
toast.BackgroundColor3 = Color3.fromRGB(96, 78, 68)
toast.BackgroundTransparency = 0.15
corner(toast, 17)
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

local tip = text(gui, "", 13, WHITE)
tip.AnchorPoint = Vector2.new(1, 0.5)
tip.AutomaticSize = Enum.AutomaticSize.X
tip.Size = UDim2.fromOffset(0, 26)
tip.BackgroundColor3 = Color3.fromRGB(96, 78, 68)
tip.BackgroundTransparency = 0.1
corner(tip, 13)
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
		tip.Position = UDim2.fromOffset(b.AbsolutePosition.X - 8, b.AbsolutePosition.Y + b.AbsoluteSize.Y / 2)
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
--   ⏭ DAY 패스: 아침·밤이면 다음 DAY 아침으로, 영업 중이면 목표를 채운 걸로 치고 마감
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
chatMenu.Size = UDim2.fromOffset(110, 4 * 40)
chatMenu.Visible = false
chatMenu.Parent = gui
list(chatMenu, Enum.FillDirection.Vertical, 4)
local function say(index: number)
	chatEvent:FireServer(index)
	chatMenu.Visible = false
end
for i, line in Config.QuickChat do
	local b = button(chatMenu, `{i}  {line}`, UDim2.fromOffset(110, 36), PAPER, INK)
	b.LayoutOrder = i
	b.TextSize = 14
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
local recipe = frame(gui, UDim2.fromOffset(360, 60))
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
	local title = text(recipe, "레시피북", 18, CORAL, ROUND)
	title.Size = UDim2.new(1, 0, 0, 22)
	title.TextXAlignment = Enum.TextXAlignment.Left
	for i, menu in state.menus do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = i
		row.Parent = recipe
		list(row, Enum.FillDirection.Vertical, 2)
		local name = text(row, `{menu.name}  ·  {menu.price}{if menu.isNew then "  NEW" else ""}`, 15, INK)
		name.Size = UDim2.new(1, 0, 0, 18)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local steps = text(row, menu.steps, 13, MUTED)
		steps.Size = UDim2.new(1, 0, 0, 0)
		steps.AutomaticSize = Enum.AutomaticSize.Y
		steps.TextXAlignment = Enum.TextXAlignment.Left
		steps.LayoutOrder = 1
	end
	local keys = text(recipe, "E 집기·놓기·담기·내기·치우기  |  F 길게 조합·토핑·불 끄기·설거지", 12, MUTED)
	keys.Size = UDim2.new(1, 0, 0, 16)
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

local holding = text(gui, "", 15, INK)
holding.AnchorPoint = Vector2.new(0.5, 1)
holding.Position = UDim2.new(0.5, 0, 1, -14)
holding.Size = UDim2.fromOffset(0, 32)
holding.AutomaticSize = Enum.AutomaticSize.X
holding.BackgroundColor3 = PAPER
holding.BackgroundTransparency = 0.05
corner(holding, 16)
pad(holding, 14, 0)
holding.Visible = false
local function updateHolding()
	local value = player:GetAttribute("Holding")
	holding.Visible = typeof(value) == "string"
	holding.Text = if typeof(value) == "string" then `들고 있는 것: {value}` else ""
end
player:GetAttributeChangedSignal("Holding"):Connect(updateHolding)
updateHolding()

local PANEL_HEIGHT = 480

-- ── 아침·밤 창: 정산·새 메뉴 + 상점 ──

local center = frame(gui, UDim2.fromOffset(740, PANEL_HEIGHT))
center.AnchorPoint = Vector2.new(0.5, 0.5)
center.Position = UDim2.fromScale(0.5, 0.52)
local scale = Instance.new("UIScale")
scale.Parent = center
pad(center, 22, 18)
UiDeco.header(center, 44, 16, Vector2.new(22, 18))

local heading = text(center, "", 30, CORAL, ROUND)

-- 새 규칙 카드: 그날 새로 생기는 규칙(글 한 줄로는 눈에 잘 안 띄었다)
local ruleCard = frame(center, UDim2.new(1, 0, 0, 78))
ruleCard.Position = UDim2.fromOffset(0, 44)
ruleCard.BackgroundColor3 = Color3.fromRGB(255, 234, 222)
ruleCard.Visible = false
local ruleBorder = ruleCard:FindFirstChildOfClass("UIStroke")
if ruleBorder then
	ruleBorder.Color = CORAL
	ruleBorder.Thickness = 3
end
local ruleIcon = text(ruleCard, "📢", 28, CORAL)
ruleIcon.Position = UDim2.fromOffset(8, 0)
ruleIcon.Size = UDim2.fromOffset(44, 78)
local ruleTitle = text(ruleCard, "새 규칙!", 18, CORAL, ROUND)
ruleTitle.Position = UDim2.fromOffset(56, 7)
ruleTitle.Size = UDim2.new(1, -66, 0, 22)
ruleTitle.TextXAlignment = Enum.TextXAlignment.Left
local ruleBody = text(ruleCard, "", 15, INK)
ruleBody.Position = UDim2.fromOffset(56, 29)
ruleBody.Size = UDim2.new(1, -66, 0, 44)
ruleBody.TextXAlignment = Enum.TextXAlignment.Left
ruleBody.TextYAlignment = Enum.TextYAlignment.Top

-- 정산 숫자 카드(밤): 매출 · 코인 · 받은 손님 · 돌아간 손님. 글 몇 줄로는 작고 잘 안 보였다.
type Tile = { box: Frame, label: TextLabel, value: TextLabel, sub: TextLabel }
local stats = Instance.new("Frame")
stats.BackgroundTransparency = 1
stats.Position = UDim2.fromOffset(0, 46)
stats.Size = UDim2.new(1, 0, 0, 100)
stats.Visible = false
stats.Parent = center
list(stats, Enum.FillDirection.Horizontal, 10)
local tiles: { Tile } = {}
for i = 1, 4 do
	local box = frame(stats, UDim2.new(0.25, -8, 1, 0))
	box.LayoutOrder = i
	box.BackgroundColor3 = Color3.fromRGB(255, 245, 234)
	local label = text(box, "", 15, MUTED)
	label.Position = UDim2.fromOffset(0, 8)
	label.Size = UDim2.new(1, 0, 0, 20)
	local value = text(box, "", 32, INK, ROUND)
	value.Position = UDim2.fromOffset(0, 30)
	value.Size = UDim2.new(1, 0, 0, 40)
	local sub = text(box, "", 13, MUTED)
	sub.Position = UDim2.fromOffset(0, 72)
	sub.Size = UDim2.new(1, 0, 0, 20)
	table.insert(tiles, { box = box, label = label, value = value, sub = sub })
end

-- 새 메뉴 카드: 오늘(아침)·내일(밤 정산)의 새 메뉴를 그림·이름·값·만드는 순서로 크게 보여 준다
local MENU_CARD_HEIGHT = 96
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
menuView.Position = UDim2.fromOffset(12, 10)
menuView.Size = UDim2.fromOffset(76, 76)
menuView.Ambient = Color3.fromRGB(200, 190, 196)
menuView.LightColor = Color3.fromRGB(255, 246, 250)
menuView.LightDirection = Vector3.new(-1, -2, -1)
corner(menuView, 38)
menuView.Parent = menuCard
local menuTitle = text(menuCard, "", 17, Color3.fromRGB(70, 140, 200), ROUND)
menuTitle.Position = UDim2.fromOffset(102, 8)
menuTitle.Size = UDim2.new(1, -112, 0, 22)
menuTitle.TextXAlignment = Enum.TextXAlignment.Left
local menuName = text(menuCard, "", 20, INK)
menuName.Position = UDim2.fromOffset(102, 32)
menuName.Size = UDim2.new(1, -112, 0, 26)
menuName.TextXAlignment = Enum.TextXAlignment.Left
menuName.RichText = true
local menuSteps = text(menuCard, "", 15, INK)
menuSteps.Position = UDim2.fromOffset(102, 60)
menuSteps.Size = UDim2.new(1, -112, 0, 30)
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

local function setTile(index: number, label: string, value: string, color: Color3, sub: string)
	local tile = tiles[index]
	tile.label.Text = label
	tile.value.Text = value
	tile.value.TextColor3 = color
	tile.sub.Text = sub
end
heading.Size = UDim2.new(1, 0, 0, 36)
heading.TextXAlignment = Enum.TextXAlignment.Left

-- 글이 길면 이 칸 안에서 스크롤된다(아래 버튼과 겹치지 않게)
local summaryBox = Instance.new("ScrollingFrame")
summaryBox.BackgroundTransparency = 1
summaryBox.BorderSizePixel = 0
summaryBox.Position = UDim2.fromOffset(0, 46)
summaryBox.Size = UDim2.new(1, 0, 1, -110)
summaryBox.CanvasSize = UDim2.new()
summaryBox.AutomaticCanvasSize = Enum.AutomaticSize.Y
summaryBox.ScrollBarThickness = 6
summaryBox.ScrollBarImageColor3 = LINE
summaryBox.Parent = center
local summary = text(summaryBox, "", 17, INK)
summary.Size = UDim2.new(1, -12, 0, 0)
summary.AutomaticSize = Enum.AutomaticSize.Y
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.TextYAlignment = Enum.TextYAlignment.Top
summary.RichText = true
summary.LineHeight = 1.15

local startButton = button(center, "", UDim2.fromOffset(190, 48), CORAL)
startButton.AnchorPoint = Vector2.new(1, 1)
startButton.Position = UDim2.fromScale(1, 1)
startButton.TextSize = 18
startButton.Activated:Connect(function()
	startEvent:FireServer()
end)
local browseButton = button(center, "가게 둘러보기", UDim2.fromOffset(110, 48), PAPER, INK)
browseButton.AnchorPoint = Vector2.new(0, 1)
browseButton.Position = UDim2.fromScale(0, 1)
stroke(browseButton)
-- 내 동물 고르기: 동물 고르기 창(AnimalPicker)을 연다. 창은 LocalPlayer 속성 AnimalPicker만 본다.
local animalButton = button(center, "동물 고르기", UDim2.fromOffset(150, 48), PAPER, INK)
animalButton.AnchorPoint = Vector2.new(0, 1)
animalButton.Position = UDim2.new(0, 120, 1, 0)
animalButton.TextSize = 15
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
local shopButton = button(center, "상점", UDim2.fromOffset(96, 48), GOLD)
shopButton.AnchorPoint = Vector2.new(0, 1)
shopButton.Position = UDim2.new(0, 280, 1, 0)
shopButton.TextSize = 16
shopButton.Activated:Connect(function()
	player:SetAttribute("ShopOpen", true)
end)
local tutorialButton = button(center, "튜토리얼", UDim2.fromOffset(96, 48), PAPER, CORAL)
tutorialButton.AnchorPoint = Vector2.new(0, 1)
tutorialButton.Position = UDim2.new(0, 386, 1, 0)
tutorialButton.TextSize = 15
stroke(tutorialButton)
tutorialButton.Activated:Connect(function()
	tutorialEvent:FireServer(true)
end)
player:GetAttributeChangedSignal("Animal"):Connect(updateAnimal)
updateAnimal()

-- 창을 접었을 때 다시 여는 버튼
local reopen = button(gui, "준비 화면 열기", UDim2.fromOffset(170, 44), CORAL)
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

-- 형광펜: 중요한 말 뒤에 연분홍(경고·빚)이나 연하늘(목표·메뉴) 배경을 깐다(RichText mark)
local function pink(value: string): string
	return `<mark color="#ffd6e4" transparency="0">{value}</mark>`
end
local function sky(value: string): string
	return `<mark color="#d2eafb" transparency="0">{value}</mark>`
end

local function menuLines(onlyNew: boolean): string
	local lines = {}
	for _, menu in state.menus do
		if not onlyNew or menu.isNew then
			table.insert(lines, `{sky(`<b>{menu.name}</b>`)} ({menu.price})\n<font color="#968276">{menu.steps}</font>`)
		end
	end
	return table.concat(lines, "\n")
end

local function renderCenter()
	local phase = state.phase
	local d = state.upcomingDay
	local hasRules = #state.rules > 0 and (phase == "morning" or state.passed)
	-- 위에서부터: (밤) 숫자 카드 → 새 규칙 카드 → 글
	local y = 46
	stats.Visible = phase == "night"
	if phase == "night" then
		y += 110
	end
	ruleCard.Visible = hasRules
	ruleCard.Position = UDim2.fromOffset(0, y)
	ruleTitle.Text = if phase == "morning" then "새 규칙!" else "내일의 새 규칙!"
	ruleBody.Text = table.concat(state.rules, " ")
	if hasRules then
		y += 88
	end
	-- 새 메뉴 카드(아침: 오늘, 밤: 목표를 넘겼을 때 내일)
	local fresh = {}
	for _, menu in state.menus do
		if menu.isNew then
			table.insert(fresh, menu)
		end
	end
	local showMenus = #fresh > 0 and (phase == "morning" or state.passed)
	menuCard.Visible = showMenus
	if showMenus then
		menuCard.Position = UDim2.fromOffset(0, y)
		showMenuCard(fresh, if phase == "morning" then "🍨 오늘의 새 메뉴!" else "🍨 내일의 새 메뉴!")
		y += MENU_CARD_HEIGHT + 10
	end
	summaryBox.Position = UDim2.fromOffset(0, y)
	summaryBox.Size = UDim2.new(1, 0, 1, -(y + 64))
	summaryBox.CanvasPosition = Vector2.zero
	heading.RichText = true
	if phase == "morning" then
		heading.Text = `DAY {d}`
		local refund = pink("<b>목표를 못 넘기면 그날 번 코인은 반납해요!</b>")
		local intro = if d == 1 then `동물 손님들이 카운터에 와서 주문해요.\n말풍선의 디저트를 만들어 손님 앞 자리에 내 주세요.\n아이스크림·음료는 손에 든 채로, 와플·케이크는 쟁반에 담아 내요.\n{refund}` else `오늘도 달콤하게!\n{refund}`
		local debt = if state.debt > 0 then `\n{pink(`남은 빚 <b>{state.debt}</b>`)} · 밤마다 이자 {math.floor(Config.Debt.interest * 100 + 0.5)}%가 붙어요. 상점에서 원하는 만큼 갚아요` else "\n빚 없음!"
		local tutorial = if d == 1 then `\n처음이면 아래 {sky("<b>튜토리얼</b>")}부터!` else ""
		summary.Text = `{intro}\n\n{sky(`목표 매출 <b>{state.target}</b>`)} · 영업 {state.daySeconds}초{debt}\n\n<b>메뉴</b>\n{menuLines(false)}\n\n<font color="#968276"><b>E</b> 집기·놓기·담기·내기·치우기 / <b>F 길게</b> 조합·토핑·불 끄기·설거지\n<b>R</b> 레시피북 / <b>C</b> 카메라 시점 / <b>1~4</b> 말풍선</font>{tutorial}`
		startButton.Text = `DAY {d} 영업 시작`
	else
		local today = state.today
		heading.Text = `DAY {state.day} 정산   ` .. (if state.passed then `<font color="#6fa868">목표 달성!</font>` else `<font color="#e0705a">목표 미달</font>`)
		setTile(1, "매출 / 목표", `{today.sales} / {state.target}`, if state.passed then SAGE else CORAL, if state.passed then "다음 날로!" else "같은 날 다시 도전")
		if state.passed then
			setTile(2, "받은 코인", `+{today.sales}`, GOLD, "코인에 들어왔어요")
		else
			setTile(2, "반납한 코인", `-{today.refunded}`, CORAL, "목표를 넘겨야 가져요")
		end
		setTile(3, "받은 손님", `{today.served}명`, INK, `팁 {today.tips}`)
		setTile(4, "돌아간 손님", `{today.missed}명`, if today.missed > 0 then CORAL else INK, if today.missed > 0 then "더 빨리 내 봐요" else "완벽해요!")
		local night = state.debtNight
		local debt = if night.interest > 0 then `<b>빚</b>  오늘 밤 이자 +{night.interest} → {pink(`남은 빚 <b>{state.debt}</b>`)} (상점에서 원하는 만큼 갚아요)` elseif state.debt <= 0 then sky("<b>빚 없음!</b>") else ""
		summary.Text = debt
		startButton.Text = if state.passed then `DAY {d} 영업 시작` else `DAY {d} 다시 도전`
	end
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
	local s = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.6, 1)
	for _, u in scales do
		u.Scale = s
	end
	scale.Scale = math.min(s, (size.X - 40) / 740, (size.Y - 80) / PANEL_HEIGHT)
	local top = math.floor(56 * s)
	toast.Position = UDim2.new(0.5, 0, 0, top)
	side.Position = UDim2.new(1, -10, 0, top)
	coinGain.Position = UDim2.new(1, -math.floor(214 * s), 0, math.floor(12 * s))
	recipe.Position = UDim2.new(1, -math.floor(10 + 56 * s), 0, top)
	chatMenu.Position = UDim2.new(1, -math.floor(10 + 56 * s), 0, top + math.floor(54 * s))
end
local currentCamera = workspace.CurrentCamera
if currentCamera then
	currentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
end

local function salesText()
	salesLabel.Text = `오늘 매출 {math.floor(salesValue.Value + 0.5)} / 목표 {state.target}`
end
salesValue:GetPropertyChangedSignal("Value"):Connect(salesText)

-- 영업을 시작할 때 그날 새 규칙을 화면 위에 잠깐 크게 보여 준다
local dayRule = frame(gui, UDim2.fromOffset(560, 0))
dayRule.AnchorPoint = Vector2.new(0.5, 0)
dayRule.Position = UDim2.new(0.5, 0, 0, 100)
dayRule.AutomaticSize = Enum.AutomaticSize.Y
dayRule.BackgroundColor3 = Color3.fromRGB(255, 234, 222)
dayRule.Visible = false
pad(dayRule, 16, 12)
local dayRuleText = text(dayRule, "", 16, INK)
dayRuleText.Size = UDim2.new(1, 0, 0, 0)
dayRuleText.AutomaticSize = Enum.AutomaticSize.Y
dayRuleText.RichText = true
local dayRuleScale = Instance.new("UIScale")
dayRuleScale.Parent = dayRule
local lastPhase = ""

local function applyState(incoming: State)
	state = incoming
	local phase = state.phase
	if phase == "countdown" and lastPhase ~= "countdown" and #state.rules > 0 then
		dayRuleText.Text = `<font color="#ec8464"><b>📢 새 규칙!</b></font>  {table.concat(state.rules, " ")}`
		dayRule.Visible = true
		task.delay(9, function()
			dayRule.Visible = false
		end)
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
	elseif state.today.sales < salesValue.Value then
		salesValue.Value = state.today.sales -- 새 날: 바로 0으로
		salesText()
	else
		TweenService:Create(salesValue, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = state.today.sales }):Play()
		salesText()
	end
	progressBack.Visible = not tutorial
	if tutorial then
		timeLabel.Text = ""
	end
	local before = shownWallet
	if before == nil then
		coinValue.Value = state.wallet
	else
		local rising = state.wallet > before
		TweenService:Create(coinValue, TweenInfo.new(if rising then 0.7 else 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = state.wallet }):Play()
		if rising then
			coinPop.Scale = 1.5
			TweenService:Create(coinPop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	debtLabel.Text = if state.debt > 0 then `빚 {state.debt}` else "빚 없음"
	if before and state.wallet > before then
		coinGain.Text = `+{state.wallet - before}`
		coinGain.Visible = true
		coinGain.TextTransparency = 0
		local fade = TweenService:Create(coinGain, TweenInfo.new(1.2), { TextTransparency = 1 })
		fade:Play()
	end
	shownWallet = state.wallet
	TweenService:Create(progressFill, TweenInfo.new(0.5), { Size = UDim2.fromScale(math.clamp(state.today.sales / math.max(state.target, 1), 0, 1), 1) }):Play()
	if inMenu then
		renderCenter()
	end
	renderRecipe()
	applyScale()
	dayRuleScale.Scale = scales[1].Scale -- 위 바와 같은 크기로
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
