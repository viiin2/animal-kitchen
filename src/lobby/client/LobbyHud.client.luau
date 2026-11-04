--!strict
-- 로비 화면: 아래에 "혼자 바로 시작" 버튼과 짧은 알림만.
-- 위쪽 안내 카드(제목·팀 짜는 법·내 최고 기록)는 글만 많고 커서 뺐다. 팀 짜는 법은 광장 간판과 발판 팻말이,
-- 내 최고 기록은 머리 위 팻말이 보여 준다. 발판·팀·순간이동 판정은 모두 서버(Lobby.server)가 한다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local soloEvent = remotes:WaitForChild(Config.Lobby.remotes.Solo) :: RemoteEvent
local toastEvent = remotes:WaitForChild(Config.Lobby.remotes.Toast) :: RemoteEvent

local PINK = Color3.fromRGB(240, 128, 160)
local PINK_DEEP = Color3.fromRGB(212, 96, 134)
local WHITE = Color3.new(1, 1, 1)

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "LobbyHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent: Instance, value: string, size: number, color: Color3, font: Enum.Font?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = color
	label.Text = value
	label.TextWrapped = true
	label.Parent = parent
	return label
end

-- 혼자 바로 시작: 말랑한 사탕 버튼. 진분홍 받침 위에 분홍 알약, 위쪽에 하얀 광택, 왼쪽에 🍦 동그란 배지.
-- 누르면 받침 쪽으로 쏙 내려가며 꾹 눌렸다가 통 튀어 오른다(맨 코랄 알약은 밋밋했다).
local BUTTON_W, BUTTON_H, DEPTH = 214, 52, 5
local soloHolder = Instance.new("Frame") -- 화면 크기 맞춤(UIScale)은 여기, 눌림 효과는 안쪽 버튼에
soloHolder.AnchorPoint = Vector2.new(0.5, 1)
soloHolder.Position = UDim2.new(0.5, 0, 1, -22)
soloHolder.Size = UDim2.fromOffset(BUTTON_W, BUTTON_H + DEPTH)
soloHolder.BackgroundTransparency = 1
soloHolder.Parent = gui

local soloBase = Instance.new("Frame")
soloBase.Position = UDim2.fromOffset(0, DEPTH)
soloBase.Size = UDim2.fromOffset(BUTTON_W, BUTTON_H)
soloBase.BackgroundColor3 = PINK_DEEP
soloBase.BorderSizePixel = 0
corner(soloBase, BUTTON_H // 2)
soloBase.Parent = soloHolder

local solo = Instance.new("TextButton")
solo.Size = UDim2.fromOffset(BUTTON_W, BUTTON_H)
solo.BackgroundColor3 = PINK
solo.BorderSizePixel = 0
solo.AutoButtonColor = false
solo.Text = ""
solo.ZIndex = 2
corner(solo, BUTTON_H // 2)
solo.Parent = soloHolder
local soloRing = Instance.new("UIStroke")
soloRing.Color = WHITE
soloRing.Thickness = 3
soloRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
soloRing.Parent = solo

local shine = Instance.new("Frame") -- 위쪽 광택
shine.Position = UDim2.fromOffset(58, 6)
shine.Size = UDim2.new(1, -86, 0, 8)
shine.BackgroundColor3 = WHITE
shine.BackgroundTransparency = 0.6
shine.BorderSizePixel = 0
shine.ZIndex = 3
corner(shine, 4)
shine.Parent = solo

local soloIcon = text(solo, "🍦", 21, PINK)
soloIcon.AnchorPoint = Vector2.new(0, 0.5)
soloIcon.Position = UDim2.new(0, 7, 0.5, 0)
soloIcon.Size = UDim2.fromOffset(38, 38)
soloIcon.BackgroundColor3 = WHITE
soloIcon.BackgroundTransparency = 0
soloIcon.Rotation = -10
soloIcon.ZIndex = 3
corner(soloIcon, 19)

local soloLabel = text(solo, "혼자 바로 시작", 20, WHITE, Enum.Font.GothamBlack)
soloLabel.Position = UDim2.fromOffset(48, 0)
soloLabel.Size = UDim2.new(1, -58, 1, 0)
soloLabel.ZIndex = 3
local soloLabelEdge = Instance.new("UIStroke") -- 글자에 옅은 진분홍 테두리
soloLabelEdge.Color = PINK_DEEP
soloLabelEdge.Thickness = 1.5
soloLabelEdge.Transparency = 0.3
soloLabelEdge.Parent = soloLabel

-- 손맛: 올리면 살짝 커지고, 누르면 받침으로 쏙 내려가며 꾹, 떼면 통
local soloBounce = Instance.new("UIScale")
soloBounce.Parent = solo
local hovering = false
local function ease(seconds: number, style: Enum.EasingStyle): TweenInfo
	return TweenInfo.new(seconds, style, Enum.EasingDirection.Out)
end
local function rest()
	TweenService:Create(soloBounce, ease(0.3, Enum.EasingStyle.Back), { Scale = if hovering then 1.05 else 1 }):Play()
	TweenService:Create(solo, ease(0.3, Enum.EasingStyle.Back), { Position = UDim2.fromOffset(0, 0) }):Play()
end
solo.MouseEnter:Connect(function()
	hovering = true
	TweenService:Create(soloBounce, ease(0.15, Enum.EasingStyle.Quad), { Scale = 1.05 }):Play()
end)
solo.MouseLeave:Connect(function()
	hovering = false
	rest()
end)
solo.MouseButton1Down:Connect(function()
	TweenService:Create(soloBounce, ease(0.08, Enum.EasingStyle.Quad), { Scale = 0.94 }):Play()
	TweenService:Create(solo, ease(0.08, Enum.EasingStyle.Quad), { Position = UDim2.fromOffset(0, DEPTH - 1) }):Play()
end)
solo.MouseButton1Up:Connect(rest)
solo.Activated:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then -- 터치·게임패드: 한 번 꾹-통
		soloBounce.Scale = 0.94
		solo.Position = UDim2.fromOffset(0, DEPTH - 1)
		rest()
	end
	soloEvent:FireServer()
end)

-- 알림
local toast = text(gui, "", 19, WHITE)
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -96)
toast.Size = UDim2.fromOffset(620, 42)
toast.BackgroundColor3 = Color3.fromRGB(96, 78, 68)
toast.BackgroundTransparency = 0.15
corner(toast, 21)
toast.Visible = false
local toastSeq = 0
toastEvent.OnClientEvent:Connect(function(message: string)
	toastSeq += 1
	local seq = toastSeq
	toast.Text = message
	toast.Visible = true
	task.delay(3, function()
		if seq == toastSeq then
			toast.Visible = false
		end
	end)
end)

-- 창이 작으면 같이 줄이고, 커도 조금만 키운다
local scaled: { GuiObject } = { soloHolder, toast }
local scales: { UIScale } = {}
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
	local s = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.6, 1.1)
	for _, u in scales do
		u.Scale = s
	end
end
local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
end
applyScale()
