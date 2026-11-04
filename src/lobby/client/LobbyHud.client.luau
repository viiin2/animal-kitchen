--!strict
-- 로비 화면: 위에 안내 카드(어떻게 팀을 짜는지), 내 최고 기록, 아래에 "혼자 바로 시작" 버튼, 짧은 알림.
-- 발판·팀·순간이동 판정은 모두 서버(Lobby.server)가 한다. 내 기록은 서버가 넣는 속성 BestDay·BestSales를 본다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local soloEvent = remotes:WaitForChild(Config.Lobby.remotes.Solo) :: RemoteEvent
local toastEvent = remotes:WaitForChild(Config.Lobby.remotes.Toast) :: RemoteEvent

local INK = Color3.fromRGB(86, 66, 56)
local PAPER = Color3.fromRGB(255, 251, 244)
local LINE = Color3.fromRGB(236, 220, 202)
local CORAL = Color3.fromRGB(236, 132, 100)
local GOLD = Color3.fromRGB(196, 140, 48)
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

-- 안내 카드
local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0.5, 0)
card.Position = UDim2.new(0.5, 0, 0, 12)
card.Size = UDim2.fromOffset(620, 128)
card.BackgroundColor3 = PAPER
card.BorderSizePixel = 0
corner(card, 18)
local stroke = Instance.new("UIStroke")
stroke.Color = LINE
stroke.Thickness = 2
stroke.Parent = card
card.Parent = gui
local title = text(card, "🍦 동물 디저트 카페 로비", 26, CORAL, Enum.Font.FredokaOne)
title.Position = UDim2.fromOffset(0, 10)
title.Size = UDim2.new(1, 0, 0, 32)
local howTo = text(card, `가게 문 발판에 올라서면 한 팀(1~{Config.Lobby.teamSize}명)!\n{Config.Lobby.teamSize}명이 모이거나 {Config.Lobby.waitSeconds}초가 지나면 가게로 출발해요.`, 18, INK)
howTo.Position = UDim2.fromOffset(16, 44)
howTo.Size = UDim2.new(1, -32, 0, 48)
local record = text(card, "", 18, GOLD)
record.Position = UDim2.fromOffset(16, 96)
record.Size = UDim2.new(1, -32, 0, 24)

local function updateRecord()
	local day = player:GetAttribute("BestDay")
	local sales = player:GetAttribute("BestSales")
	record.Text = if typeof(day) == "number" and day > 0
		then `🏆 내 최고 기록: DAY {day}까지 · 총 매출 {if typeof(sales) == "number" then sales else 0}`
		else "🆕 아직 기록이 없어요. 첫 가게를 열어 봐요!"
end
player:GetAttributeChangedSignal("BestDay"):Connect(updateRecord)
player:GetAttributeChangedSignal("BestSales"):Connect(updateRecord)
updateRecord()

-- 혼자 바로 시작
local solo = Instance.new("TextButton")
solo.AnchorPoint = Vector2.new(0.5, 1)
solo.Position = UDim2.new(0.5, 0, 1, -24)
solo.Size = UDim2.fromOffset(240, 58)
solo.BackgroundColor3 = CORAL
solo.BorderSizePixel = 0
solo.Font = Enum.Font.GothamBold
solo.TextSize = 22
solo.TextColor3 = WHITE
solo.Text = "혼자 바로 시작"
corner(solo, 16)
solo.Parent = gui
solo.Activated:Connect(function()
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

-- 창이 작으면 같이 줄이고, 크면 조금 키운다
local scaled: { GuiObject } = { card, solo, toast }
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
	local s = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.6, 1.3)
	for _, u in scales do
		u.Scale = s
	end
end
local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
end
applyScale()
