--!strict
-- 오늘의 MVP: 영업이 끝나 밤 정산으로 넘어갈 때("오늘 번 돈" 다음) 정산 창 위에 잠깐 띄운다.
-- 서버(Days)가 부문마다 가장 잘한 사람을 골라 상태(mvp)로 보내 준다: 서빙왕·코인왕·아이스크림 장인·청소왕·불 끈 영웅.
-- 카드마다 그 친구의 동물 인형(요리사 차림)이 빙글빙글 돈다. "좋아요!"를 누르거나 10초가 지나면 닫힌다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local UiDeco = require(ReplicatedStorage.Shared.UiDeco)
local AnimalLooks = require(ReplicatedStorage.Shared.AnimalLooks)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stateEvent = remotes:WaitForChild(Config.Remotes.State) :: RemoteEvent

type Card = { icon: string, title: string, name: string, detail: string, animal: number }

local INK = Color3.fromRGB(110, 76, 90)
local MUTED = Color3.fromRGB(168, 136, 150)
local PAPER = Color3.fromRGB(255, 248, 251)
local CARD = Color3.fromRGB(255, 238, 245)
local CORAL = Color3.fromRGB(236, 132, 100)
local GOLD = Color3.fromRGB(232, 176, 76)
local WHITE = Color3.new(1, 1, 1)

local CARD_WIDTH, HEIGHT = 136, 330
local AUTO_CLOSE = 10

local player = Players.LocalPlayer
local lastPhase = ""
local models: { Model } = {}
local openedAt = 0

local gui = Instance.new("ScreenGui")
gui.Name = "MvpWindow"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 9
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, value: string, size: number, color: Color3, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = value
	l.TextWrapped = true
	l.Parent = parent
	return l
end

local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.fromRGB(60, 40, 50)
dim.BackgroundTransparency = 0.5
dim.BorderSizePixel = 0
dim.Parent = gui

local window = Instance.new("Frame")
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromOffset(400, HEIGHT)
window.BackgroundColor3 = PAPER
window.BorderSizePixel = 0
corner(window, 22)
local border = Instance.new("UIStroke")
border.Color = GOLD
border.Thickness = 3
border.Parent = window
window.Parent = gui
UiDeco.header(window, 46, 22)
local scale = Instance.new("UIScale")
scale.Parent = window

local title = label(window, "오늘의 MVP 🏆", 26, CORAL, Enum.Font.FredokaOne)
title.Position = UDim2.fromOffset(0, 14)
title.Size = UDim2.new(1, 0, 0, 34)

local row = Instance.new("Frame")
row.BackgroundTransparency = 1
row.Position = UDim2.fromOffset(16, 58)
row.Size = UDim2.new(1, -32, 0, 210)
row.Parent = window
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 10)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = row

local ok = Instance.new("TextButton")
ok.AnchorPoint = Vector2.new(0.5, 1)
ok.Position = UDim2.new(0.5, 0, 1, -14)
ok.Size = UDim2.fromOffset(150, 42)
ok.BackgroundColor3 = CORAL
ok.BorderSizePixel = 0
ok.Font = Enum.Font.GothamBold
ok.TextSize = 17
ok.TextColor3 = WHITE
ok.Text = "좋아요!"
corner(ok, 14)
ok.Parent = window

local function close()
	if not gui.Enabled then
		return
	end
	UiDeco.popOut(scale, function()
		gui.Enabled = false
		table.clear(models)
	end)
end
ok.Activated:Connect(close)

local function makeCard(card: Card, order: number)
	local box = Instance.new("Frame")
	box.Size = UDim2.fromOffset(CARD_WIDTH, 210)
	box.BackgroundColor3 = CARD
	box.BorderSizePixel = 0
	box.LayoutOrder = order
	corner(box, 16)
	box.Parent = row

	local view = Instance.new("ViewportFrame")
	view.BackgroundTransparency = 1
	view.Size = UDim2.new(1, 0, 0, 110)
	view.Ambient = Color3.fromRGB(200, 190, 196)
	view.LightColor = Color3.fromRGB(255, 246, 250)
	view.LightDirection = Vector3.new(0.4, -1, 0.7)
	view.Parent = box
	local model = AnimalLooks.preview(card.animal)
	model.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0.8, -11), Vector3.new(0, 0.1, 0))
	camera.Parent = view
	view.CurrentCamera = camera
	table.insert(models, model)

	local kind = label(box, `{card.icon} {card.title}`, 14, CORAL, Enum.Font.GothamBold)
	kind.Position = UDim2.fromOffset(4, 114)
	kind.Size = UDim2.new(1, -8, 0, 20)
	local name = label(box, card.name, 16, INK, Enum.Font.GothamBold)
	name.Position = UDim2.fromOffset(4, 138)
	name.Size = UDim2.new(1, -8, 0, 22)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local detail = label(box, card.detail, 13, MUTED, Enum.Font.GothamBold)
	detail.Position = UDim2.fromOffset(4, 164)
	detail.Size = UDim2.new(1, -8, 0, 36)

	-- 하나씩 톡톡 튀어나온다
	local pop = Instance.new("UIScale")
	pop.Scale = 0.3
	pop.Parent = box
	TweenService:Create(pop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.12 * order), { Scale = 1 }):Play()
end

local function open(cards: { Card })
	for _, child in row:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(models)
	for i, card in cards do
		makeCard(card, i)
	end
	local width = math.max(400, #cards * (CARD_WIDTH + 10) + 32)
	window.Size = UDim2.fromOffset(width, HEIGHT)
	local camera = workspace.CurrentCamera
	if camera then
		local size = camera.ViewportSize
		scale.Scale = math.clamp(math.min((size.X - 24) / width, (size.Y - 40) / HEIGHT), 0.4, 1)
	end
	openedAt = os.clock()
	gui.Enabled = true
	UiDeco.popIn(scale, scale.Scale)
end

stateEvent.OnClientEvent:Connect(function(state: { phase: string, mvp: { Card }? })
	local cards = state.mvp
	if state.phase == "night" and lastPhase == "open" and cards and #cards > 0 then
		-- 가운데서 "오늘 번 돈"이 올라간 뒤 정산 창과 함께 뜬다(Hud)
		task.delay(Config.NightIntroSeconds, function()
			if (lastPhase :: string) == "night" then -- 그 사이 다음 날로 넘어갔으면 띄우지 않는다
				open(cards)
			end
		end)
	elseif state.phase ~= "night" and gui.Enabled then
		close()
	end
	lastPhase = state.phase
end)

RunService.RenderStepped:Connect(function()
	if not gui.Enabled then
		return
	end
	if os.clock() - openedAt > AUTO_CLOSE then
		close()
		return
	end
	local angle = os.clock() * 0.9
	for _, model in models do
		model:PivotTo(CFrame.Angles(0, angle, 0))
	end
end)
