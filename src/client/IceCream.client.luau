--!strict
-- 아이스크림 만들기 창: 아이스크림 기계에서 E를 누르면 화면 아래에 열린다(손님이 보이게 위는 비워 둔다).
-- 그릇(콘·컵) → 맛 노즐을 눌러 한 층씩 쌓기(최대 3층) → 토핑 → 완성! 가운데 미리보기가 빙글빙글 돌며 바로 바뀐다.
-- 완성하면 서버(Stations)가 다시 검사해 손에 쥐여 준다. 창을 닫거나 취소하면 기계를 놓아 준다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local openEvent = remotes:WaitForChild(Config.Remotes.IceOpen) :: RemoteEvent
local makeEvent = remotes:WaitForChild(Config.Remotes.IceMake) :: RemoteEvent

local BODY = Enum.Font.GothamBold
local ROUND = Enum.Font.FredokaOne
local INK = Color3.fromRGB(110, 76, 90)
local MUTED = Color3.fromRGB(168, 136, 150)
local PAPER = Color3.fromRGB(255, 248, 251)
local PINK = Color3.fromRGB(250, 196, 212)
local PINK_DEEP = Color3.fromRGB(242, 140, 172)
local WHITE = Color3.new(1, 1, 1)

local WINDOW_HEIGHT = 340

local ice = Config.IceCream
local player = Players.LocalPlayer

local spec: Config.IceSpec = { base = "cone", flavors = {}, topping = nil }

local gui = Instance.new("ScreenGui")
gui.Name = "IceCreamWindow"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
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
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function button(parent: Instance, value: string, size: UDim2, color: Color3, textColor: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = BODY
	b.TextSize = 15
	b.TextColor3 = textColor
	b.Text = value
	b.AutoButtonColor = true
	corner(b, 12)
	b.Parent = parent
	return b
end

local function row(parent: Instance, order: number, height: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, height)
	f.LayoutOrder = order
	f.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = f
	return f
end

-- 고르는 곳의 작은 제목(크기를 정하지 않으면 기본 높이 50이라 아래 버튼과 겹친다)
local function caption(parent: Instance, value: string, order: number)
	local l = text(parent, value, 14, MUTED)
	l.Size = UDim2.new(1, 0, 0, 18)
	l.LayoutOrder = order
end

-- ── 창 ──

local window = Instance.new("Frame")
window.AnchorPoint = Vector2.new(0.5, 1)
window.Position = UDim2.new(0.5, 0, 1, -12)
window.Size = UDim2.fromOffset(700, WINDOW_HEIGHT)
window.BackgroundColor3 = PAPER
window.BorderSizePixel = 0
corner(window, 22)
stroke(window, PINK, 3)
window.Parent = gui
local scale = Instance.new("UIScale")
scale.Parent = window

local title = text(window, "아이스크림 만들기", 22, PINK_DEEP, ROUND)
title.Position = UDim2.fromOffset(22, 12)
title.Size = UDim2.fromOffset(300, 28)

-- 미리보기
local stage = Instance.new("Frame")
stage.Position = UDim2.fromOffset(20, 48)
stage.Size = UDim2.new(0, 210, 1, -64)
stage.BackgroundColor3 = Color3.fromRGB(255, 236, 244)
stage.BorderSizePixel = 0
corner(stage, 18)
stage.Parent = window
local view = Instance.new("ViewportFrame")
view.BackgroundTransparency = 1
view.Size = UDim2.new(1, 0, 1, -34)
view.Ambient = Color3.fromRGB(200, 190, 196)
view.LightColor = Color3.fromRGB(255, 246, 250)
view.LightDirection = Vector3.new(-1, -2, -1)
view.Parent = stage
local pop = Instance.new("UIScale")
pop.Parent = view
local nameLabel = text(stage, "", 14, INK)
nameLabel.Position = UDim2.new(0, 10, 1, -32)
nameLabel.Size = UDim2.new(1, -20, 0, 26)
nameLabel.TextXAlignment = Enum.TextXAlignment.Center
nameLabel.TextWrapped = true

local camera = Instance.new("Camera")
camera.FieldOfView = 30
camera.Parent = view
view.CurrentCamera = camera
local preview: Model? = nil
local spinStart = os.clock()

-- 고르는 곳: 위에서 아래로 그릇 → 맛 → 토핑 → (안내 · 취소 · 완성!) 줄. 줄마다 높이를 정해 서로 겹치지 않는다
local panel = Instance.new("Frame")
panel.BackgroundTransparency = 1
panel.Position = UDim2.fromOffset(250, 48)
panel.Size = UDim2.new(1, -270, 1, -64)
panel.Parent = window
local panelLayout = Instance.new("UIListLayout")
panelLayout.FillDirection = Enum.FillDirection.Vertical
panelLayout.Padding = UDim.new(0, 6)
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Parent = panel

caption(panel, "그릇", 1)
local baseRow = row(panel, 2, 40)
caption(panel, "맛 (누를 때마다 한 층씩, 최대 3층)", 3)
local flavorRow = row(panel, 4, 48)
caption(panel, "토핑", 5)
local toppingRow = row(panel, 6, 40)

local actions = Instance.new("Frame")
actions.BackgroundTransparency = 1
actions.Size = UDim2.new(1, 0, 0, 46)
actions.LayoutOrder = 7
actions.Parent = panel
local finish = button(actions, "완성!", UDim2.fromOffset(150, 46), PINK_DEEP, WHITE)
finish.AnchorPoint = Vector2.new(1, 0)
finish.Position = UDim2.fromScale(1, 0)
finish.Font = ROUND
finish.TextSize = 22
local cancel = button(actions, "취소", UDim2.fromOffset(90, 46), WHITE, INK)
cancel.AnchorPoint = Vector2.new(1, 0)
cancel.Position = UDim2.new(1, -160, 0, 0)
stroke(cancel, PINK, 2)
local hint = text(actions, "", 13, MUTED)
hint.Size = UDim2.new(1, -260, 1, 0)
hint.TextWrapped = true

-- ── 미리보기 그리기 ──

local function redraw(bounce: boolean)
	local old = preview
	if old then
		old:Destroy()
	end
	local model = FoodModels.build("icecream", "cooked", 0, spec)
	model.Parent = view
	preview = model
	local size = (model.PrimaryPart :: BasePart).Size
	local reach = math.max(size.Y, 2.4)
	camera.CFrame = CFrame.lookAt(Vector3.new(0, reach * 0.55, reach * 2.6), Vector3.new(0, 0, 0))
	nameLabel.Text = if #spec.flavors > 0 then Config.iceName(spec) else "맛을 골라요"
	finish.AutoButtonColor = #spec.flavors > 0
	finish.BackgroundTransparency = if #spec.flavors > 0 then 0 else 0.5
	if bounce then
		pop.Scale = 1.12
		TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
end

-- ── 버튼 ──

local baseButtons: { [string]: TextButton } = {}
local toppingButtons: { [string]: TextButton } = {}

local function paintChoices()
	for id, b in baseButtons do
		b.BackgroundColor3 = if spec.base == id then PINK else WHITE
	end
	for id, b in toppingButtons do
		local chosen = if id == "" then spec.topping == nil else spec.topping == id
		b.BackgroundColor3 = if chosen then PINK else WHITE
	end
end

for i, option in ice.bases do
	local b = button(baseRow, option.name, UDim2.fromOffset(90, 38), WHITE, INK)
	b.LayoutOrder = i
	stroke(b, PINK, 2)
	baseButtons[option.id] = b
	b.Activated:Connect(function()
		spec.base = option.id
		paintChoices()
		redraw(true)
	end)
end

for i, option in ice.flavors do
	-- 노즐 모양 동그란 버튼
	-- 어두운 맛(초코)은 글씨를 바닐라 버튼과 같은 크림색으로
	local dark = option.color.R * 0.3 + option.color.G * 0.59 + option.color.B * 0.11 < 0.5
	local cream = Config.findIceOption(ice.flavors, "vanilla")
	local b = button(flavorRow, option.name, UDim2.fromOffset(78, 46), option.color, if dark and cream then cream.color else INK)
	b.LayoutOrder = i
	corner(b, 23)
	stroke(b, WHITE, 3)
	b.Activated:Connect(function()
		if #spec.flavors >= ice.maxLayers then
			hint.Text = `{ice.maxLayers}층까지 쌓을 수 있어요`
			return
		end
		table.insert(spec.flavors, option.id)
		hint.Text = ""
		redraw(true)
	end)
end
local undo = button(flavorRow, "한 층 빼기", UDim2.fromOffset(84, 38), WHITE, MUTED)
undo.LayoutOrder = 10
undo.TextSize = 13
stroke(undo, PINK, 2)
undo.Activated:Connect(function()
	table.remove(spec.flavors)
	redraw(true)
end)

local none = button(toppingRow, "없음", UDim2.fromOffset(62, 36), WHITE, INK)
none.LayoutOrder = 0
stroke(none, PINK, 2)
toppingButtons[""] = none
none.Activated:Connect(function()
	spec.topping = nil
	paintChoices()
	redraw(true)
end)
for i, option in ice.toppings do
	local b = button(toppingRow, option.name, UDim2.fromOffset(74, 36), WHITE, INK)
	b.LayoutOrder = i
	b.TextSize = 14
	stroke(b, option.color, 2)
	toppingButtons[option.id] = b
	b.Activated:Connect(function()
		spec.topping = option.id
		paintChoices()
		redraw(true)
	end)
end

-- ── 열고 닫기 ──

local function close(send: boolean, value: Config.IceSpec?)
	if not gui.Enabled then
		return
	end
	gui.Enabled = false
	player:SetAttribute("IceWindowOpen", false)
	if send then
		makeEvent:FireServer(value)
	end
end

finish.Activated:Connect(function()
	if #spec.flavors == 0 then
		hint.Text = "맛을 한 층 이상 골라요"
		return
	end
	close(true, { base = spec.base, flavors = table.clone(spec.flavors), topping = spec.topping })
end)
cancel.Activated:Connect(function()
	close(true, nil)
end)

local function applyScale()
	local current = workspace.CurrentCamera
	if current then
		local size = current.ViewportSize
		scale.Scale = math.clamp(math.min((size.X - 24) / 700, (size.Y * 0.6) / WINDOW_HEIGHT), 0.4, 1)
	end
end

openEvent.OnClientEvent:Connect(function(open: boolean)
	if not open then
		gui.Enabled = false
		player:SetAttribute("IceWindowOpen", false)
		return
	end
	spec = { base = "cone", flavors = {}, topping = nil }
	hint.Text = ""
	paintChoices()
	redraw(false)
	applyScale()
	spinStart = os.clock()
	gui.Enabled = true
	player:SetAttribute("IceWindowOpen", true) -- 튜토리얼이 본다
end)

RunService.RenderStepped:Connect(function()
	local model = preview
	if gui.Enabled and model then
		model:PivotTo(CFrame.Angles(0, (os.clock() - spinStart) * 0.9, 0))
	end
end)
