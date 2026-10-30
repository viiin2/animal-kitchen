--!strict
-- 빠른 말풍선: 화면 아래 버튼(Config.QuickChat)을 누르면 캐릭터 머리 위에 2.5초 띄운다.
-- 글자 채팅이 불편한 모바일에서도 협동할 수 있게 한다(기획서 '주방과 역할').
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)

local BUBBLE_SECONDS = 2.5

local lastSent: { [Player]: number } = {}

local function bubble(head: BasePart, text: string)
	local old = head:FindFirstChild("QuickChat")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "QuickChat"
	gui.Size = UDim2.fromOffset(150, 40)
	gui.StudsOffset = Vector3.new(0, 3.8, 0) -- 요리사 모자 위
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.new(1, 1, 1)
	label.TextColor3 = Color3.fromRGB(30, 30, 30)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label
	label.Parent = gui
	gui.Parent = head
	Debris:AddItem(gui, BUBBLE_SECONDS)
end

Remotes.Chat.OnServerEvent:Connect(function(player: Player, index: unknown)
	if typeof(index) ~= "number" then
		return
	end
	local text = Config.QuickChat[index]
	if not text then
		return
	end
	local t = os.clock()
	local last = lastSent[player]
	if last and t - last < Config.QuickChatCooldown then
		return
	end
	lastSent[player] = t
	local character = player.Character
	local head = if character then character:FindFirstChild("Head") else nil
	if head and head:IsA("BasePart") then
		bubble(head, text)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastSent[player] = nil
end)

return {}
