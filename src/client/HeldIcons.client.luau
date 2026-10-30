--!strict
-- 친구 머리 위 아이콘: 다른 플레이어가 지금 들고 있는 것을 작은 동그라미 안에 실제 모양으로 띄운다.
-- 말(음성·채팅) 없이도 "저 친구는 밀크티를 만드는 중"을 한눈에 알게 해서, 모르는 사람끼리도 일을 나누기 쉽게 한다.
-- 서버(Stations)가 플레이어 속성 HeldItem(JSON: kind·state·spec·melt·tray)을 정해 준다. 내 것은 화면 아래 글로 보이므로 띄우지 않는다.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)

type Held = { kind: string, state: string, spec: Config.IceSpec?, melt: number, tray: boolean }

local CORAL = Color3.fromRGB(236, 132, 100)

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local icons: { [Player]: BillboardGui } = {}

local function parse(value: unknown): Held?
	if typeof(value) ~= "string" then
		return nil
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(value)
	end)
	if not ok or typeof(decoded) ~= "table" then
		return nil
	end
	local raw = decoded :: { [string]: any }
	if typeof(raw.kind) ~= "string" or typeof(raw.state) ~= "string" then
		return nil
	end
	return {
		kind = raw.kind,
		state = raw.state,
		spec = if raw.spec ~= nil then Config.validIce(raw.spec) else nil,
		melt = if typeof(raw.melt) == "number" then raw.melt else 0,
		tray = raw.tray == true,
	}
end

local function clear(player: Player)
	local gui = icons[player]
	if gui then
		gui:Destroy()
		icons[player] = nil
	end
end

local function draw(player: Player)
	clear(player)
	local held = parse(player:GetAttribute("HeldItem"))
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not held or not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "HeldIcon"
	gui.Adornee = head
	gui.Size = UDim2.new(2.4, 0, 2.4, 0) -- 스터드 단위라 멀리 있어도 캐릭터 크기에 맞는다
	gui.StudsOffset = Vector3.new(0, 3.6, 0) -- 요리사 모자 위
	gui.AlwaysOnTop = true
	gui.MaxDistance = 150
	gui.LightInfluence = 0

	local circle = Instance.new("Frame")
	circle.Size = UDim2.fromScale(1, 1)
	circle.BackgroundColor3 = Color3.fromRGB(255, 252, 246)
	circle.BorderSizePixel = 0
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = circle
	local border = Instance.new("UIStroke")
	border.Color = CORAL
	border.Thickness = 2
	border.Parent = circle
	circle.Parent = gui

	local view = Instance.new("ViewportFrame")
	view.BackgroundTransparency = 1
	view.Size = UDim2.fromScale(0.86, 0.86)
	view.Position = UDim2.fromScale(0.07, 0.07)
	view.Ambient = Color3.fromRGB(200, 190, 196)
	view.LightColor = Color3.fromRGB(255, 246, 250)
	view.LightDirection = Vector3.new(-1, -2, -1)
	view.Parent = circle

	local model = FoodModels.build(held.kind, held.state, held.melt, held.spec)
	model.Parent = view
	local root = model.PrimaryPart :: BasePart
	if held.tray then
		local tray = FoodModels.build("plate", "")
		tray:PivotTo(CFrame.new(0, -root.Size.Y / 2 - 0.1, 0))
		tray.Parent = view
	end
	local reach = math.max(root.Size.X, root.Size.Y, root.Size.Z, if held.tray then 2.6 else 0)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.CFrame = CFrame.lookAt(Vector3.new(0, reach * 1.2, reach * 2), Vector3.new(0, 0, 0))
	camera.Parent = view
	view.CurrentCamera = camera

	gui.Parent = playerGui
	icons[player] = gui
end

local function watch(player: Player)
	if player == localPlayer then
		return
	end
	player:GetAttributeChangedSignal("HeldItem"):Connect(function()
		draw(player)
	end)
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Head", 5)
		draw(player)
	end)
	draw(player)
end

Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(clear)
for _, player in Players:GetPlayers() do
	task.spawn(watch, player)
end
