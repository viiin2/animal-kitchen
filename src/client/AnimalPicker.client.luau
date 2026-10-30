--!strict
-- 동물 고르기 창: 아침·밤 창의 "동물 고르기"(LocalPlayer 속성 AnimalPicker = true)로 연다.
-- 동물마다 요리사 차림 미리보기가 빙글빙글 돌고, 그 동물의 능력을 보여 준다. 연 동물은 "고르기", 잠긴 동물은 자물쇠와 값.
-- 잠긴 동물은 게임패스(Robux)로 사람마다 연다: 누르면 로블록스 결제 창이 뜨고, 결제가 끝나면 서버(Avatars)가 열어 준다.
-- 게임패스 id가 아직 0이면 서버가 Studio에서만 시험으로 열어 준다. 코인은 상점 업그레이드에만 쓴다.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local UiDeco = require(ReplicatedStorage.Shared.UiDeco)
local AnimalLooks = require(ReplicatedStorage.Shared.AnimalLooks)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stateEvent = remotes:WaitForChild(Config.Remotes.State) :: RemoteEvent
local animalEvent = remotes:WaitForChild(Config.Remotes.Animal) :: RemoteEvent

type Card = { view: ViewportFrame, model: Model, action: TextButton, lock: TextLabel }

local BODY = Enum.Font.GothamBold
local ROUND = Enum.Font.FredokaOne
local INK = Color3.fromRGB(110, 76, 90)
local MUTED = Color3.fromRGB(168, 136, 150)
local PAPER = Color3.fromRGB(255, 248, 251)
local CARD = Color3.fromRGB(255, 238, 245)
local PINK = Color3.fromRGB(250, 196, 212)
local CORAL = Color3.fromRGB(236, 132, 100)
local SAGE = Color3.fromRGB(134, 178, 126)
local WHITE = Color3.new(1, 1, 1)

local WIDTH, HEIGHT = 700, 540

local player = Players.LocalPlayer
local phase = "morning"

local gui = Instance.new("ScreenGui")
gui.Name = "AnimalPicker"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 8
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function text(parent: Instance, value: string, size: number, color: Color3, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font or BODY
	l.TextSize = size
	l.TextColor3 = color
	l.Text = value
	l.Parent = parent
	return l
end

local function button(parent: Instance, value: string, size: UDim2, color: Color3, textColor: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = BODY
	b.TextSize = 14
	b.TextColor3 = textColor
	b.Text = value
	corner(b, 12)
	b.Parent = parent
	return b
end

-- ── 창 ──

local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.fromRGB(60, 40, 50)
dim.BackgroundTransparency = 0.55
dim.BorderSizePixel = 0
dim.Parent = gui

local window = Instance.new("Frame")
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromOffset(WIDTH, HEIGHT)
window.BackgroundColor3 = PAPER
window.BorderSizePixel = 0
corner(window, 22)
stroke(window, PINK, 3)
window.Parent = gui
UiDeco.header(window, 40, 22)
local scale = Instance.new("UIScale")
scale.Parent = window

local title = text(window, "동물 고르기", 26, CORAL, ROUND)
title.Position = UDim2.fromOffset(24, 14)
title.Size = UDim2.fromOffset(300, 34)
title.TextXAlignment = Enum.TextXAlignment.Left
local note = text(window, "동물마다 능력이 달라요. 잠긴 동물은 Robux(게임패스)로 열고, 한 번 열면 계속 쓸 수 있어요.", 13, MUTED)
note.Position = UDim2.fromOffset(24, 48)
note.Size = UDim2.new(1, -48, 0, 18)
note.TextXAlignment = Enum.TextXAlignment.Left

local grid = Instance.new("Frame")
grid.BackgroundTransparency = 1
grid.Position = UDim2.fromOffset(24, 76)
grid.Size = UDim2.new(1, -48, 1, -140)
grid.Parent = window
local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.fromOffset(152, 206)
layout.CellPadding = UDim2.fromOffset(10, 10)
layout.FillDirectionMaxCells = 4
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = grid

local close = button(window, "닫기", UDim2.fromOffset(120, 42), WHITE, INK)
close.AnchorPoint = Vector2.new(1, 1)
close.Position = UDim2.new(1, -24, 1, -14)
close.TextSize = 16
stroke(close, PINK, 2)

-- ── 동물 카드 ──

local cards: { Card } = {}

for i, look in AnimalLooks.list do
	local card = Instance.new("Frame")
	card.BackgroundColor3 = CARD
	card.BorderSizePixel = 0
	card.LayoutOrder = i
	corner(card, 16)
	card.Parent = grid

	local view = Instance.new("ViewportFrame")
	view.BackgroundTransparency = 1
	view.Size = UDim2.new(1, 0, 0, 120)
	view.Ambient = Color3.fromRGB(200, 190, 196)
	view.LightColor = Color3.fromRGB(255, 246, 250)
	view.LightDirection = Vector3.new(0.4, -1, 0.7)
	view.Parent = card
	local model = AnimalLooks.preview(i)
	model.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.8, -11), Vector3.new(0, 0.1, 0))
	camera.Parent = view
	view.CurrentCamera = camera

	local lock = text(card, "🔒", 30, INK)
	lock.Position = UDim2.fromOffset(0, 40)
	lock.Size = UDim2.new(1, 0, 0, 40)

	local name = text(card, look.name, 15, INK)
	name.Position = UDim2.fromOffset(0, 118)
	name.Size = UDim2.new(1, 0, 0, 18)

	local perk = text(card, look.perkText, 11, CORAL)
	perk.Position = UDim2.fromOffset(8, 136)
	perk.Size = UDim2.new(1, -16, 0, 28)
	perk.TextWrapped = true

	local action = button(card, "", UDim2.new(1, -20, 0, 30), CORAL, WHITE)
	action.Position = UDim2.fromOffset(10, 168)
	action.Activated:Connect(function()
		local mine = string.split(tostring(player:GetAttribute("OwnedAnimals") or ""), ",")
		if look.pass > 0 and not table.find(mine, tostring(i)) then
			MarketplaceService:PromptGamePassPurchase(player, look.pass)
		else
			animalEvent:FireServer(i)
		end
	end)

	table.insert(cards, { view = view, model = model, action = action, lock = lock })
end

local function render()
	local current = player:GetAttribute("AnimalIndex")
	local mine = string.split(tostring(player:GetAttribute("OwnedAnimals") or ""), ",")
	for i, card in cards do
		local look = AnimalLooks.list[i]
		local owned = look.robux <= 0 or table.find(mine, tostring(i)) ~= nil
		local action = card.action
		card.lock.Visible = not owned
		-- 잠긴 동물도 어떻게 생겼는지 보이게 살짝만 어둡게 한다
		card.view.ImageColor3 = if owned then WHITE else Color3.fromRGB(170, 166, 176)
		if owned and current == i then
			action.Text = "지금 내 동물"
			action.BackgroundColor3 = WHITE
			action.TextColor3 = SAGE
			action.AutoButtonColor = false
		elseif owned then
			action.Text = "고르기"
			action.BackgroundColor3 = CORAL
			action.TextColor3 = WHITE
			action.AutoButtonColor = true
		else
			action.Text = `R$ {look.robux}로 열기`
			action.BackgroundColor3 = SAGE
			action.TextColor3 = WHITE
			action.AutoButtonColor = true
		end
	end
end

local function applyScale()
	local camera = workspace.CurrentCamera
	if camera then
		local size = camera.ViewportSize
		scale.Scale = math.clamp(math.min((size.X - 24) / WIDTH, (size.Y - 40) / HEIGHT), 0.4, 1)
	end
end

local function setOpen(open: boolean)
	gui.Enabled = open
	if open then
		applyScale()
		render()
	elseif player:GetAttribute("AnimalPicker") == true then
		player:SetAttribute("AnimalPicker", false)
	end
end

close.Activated:Connect(function()
	setOpen(false)
end)
player:GetAttributeChangedSignal("AnimalPicker"):Connect(function()
	setOpen(player:GetAttribute("AnimalPicker") == true)
end)
player:GetAttributeChangedSignal("AnimalIndex"):Connect(render)
player:GetAttributeChangedSignal("OwnedAnimals"):Connect(render)

stateEvent.OnClientEvent:Connect(function(incoming: { phase: string })
	phase = incoming.phase
	-- 영업이 시작되면 창을 닫는다
	if phase ~= "morning" and phase ~= "night" and gui.Enabled then
		setOpen(false)
	end
end)

RunService.RenderStepped:Connect(function()
	if not gui.Enabled then
		return
	end
	local angle = os.clock() * 0.8
	for _, card in cards do
		card.model:PivotTo(CFrame.Angles(0, angle, 0))
	end
end)
