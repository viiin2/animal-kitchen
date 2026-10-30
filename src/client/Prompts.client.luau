--!strict
-- 작은 프롬프트: 기본 ProximityPrompt UI(크게 떠서 화면을 가림) 대신 [E] 행동 · 놓인 것 이름 알약을 그린다.
-- 어느 기구의 프롬프트를 켤지도 여기서 정한다: 캐릭터가 바라보는 쪽에서 가장 가까운 기구 하나만 켠다.
--   기본 동작(가장 가까운 프롬프트)은 통로 건너편 조합대나 옆 상자가 잡혀서, 기구 앞에 서도 그 버튼이 안 뜨곤 했다.
--   서버는 기구마다 쓸 수 있는지(속성 On)와 기본 길게 누르는 시간(속성 Hold)만 정하고, 프롬프트 자리는 기구 앞면이다.
-- 같은 기구의 E·F 알약은 한 말풍선 안에 위아래로 쌓는다. 길게 누르는 시간에는 내 동물 능력(강아지·판다)을 곱한다.
-- 키 입력은 그대로 ProximityPromptService가 받고, 터치·마우스는 알약을 누르면 된다.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local AnimalLooks = require(ReplicatedStorage.Shared.AnimalLooks)

type Shown = { pill: TextButton, fill: Frame, adornee: Instance, connections: { RBXScriptConnection } }

local PAPER = Color3.fromRGB(255, 251, 244)
local LINE = Color3.fromRGB(236, 220, 202)
local INK = Color3.fromRGB(86, 66, 56)
local MUTED = Color3.fromRGB(150, 130, 118)
local CORAL = Color3.fromRGB(236, 132, 100)
local SAGE = Color3.fromRGB(134, 178, 126)

local REACH = 5.5 -- 이 거리(바닥 기준 스터드) 안의 기구만 고른다. 서버 판정 거리(8)보다 짧다
local TURN_COST = 2 -- 옆을 보고 있으면 2스터드, 등지고 있으면 4스터드 더 먼 것으로 친다

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local store = workspace:WaitForChild("Store")

local shown: { [ProximityPrompt]: Shown } = {}
local bubbles: { [Instance]: BillboardGui } = {} -- 기구(프롬프트 자리)마다 알약을 담는 말풍선
local points: { [ProximityPrompt]: Attachment } = {}
local holding: { [ProximityPrompt]: Tween } = {}
local held: ProximityPrompt? = nil -- 길게 누르는 중인 프롬프트(누르는 동안은 고른 기구를 바꾸지 않는다)
local heldAt = 0
local touchHeld = false -- 알약을 손가락·마우스로 누르는 중

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "탭"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return (string.gsub(prompt.GamepadKeyCode.Name, "^Button", ""))
	end
	return prompt.KeyboardKeyCode.Name
end

local function label(parent: Instance, value: string, size: number, color: Color3, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, 24)
	l.Font = Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = color
	l.Text = value
	l.LayoutOrder = order
	l.ZIndex = 2
	l.Parent = parent
	return l
end

-- ── 고르기 ──

local function track(object: Instance)
	if object:IsA("ProximityPrompt") then
		local parent = object.Parent
		if parent and parent:IsA("Attachment") then
			points[object] = parent
			object.Enabled = false
		end
	end
end
store.DescendantAdded:Connect(track)
store.DescendantRemoving:Connect(function(object: Instance)
	if object:IsA("ProximityPrompt") then
		points[object] = nil
	end
end)
for _, object in store:GetDescendants() do
	track(object)
end

-- 길게 누르기가 정말 계속되는지. 끝났다는 신호(PromptButtonHoldEnded)는 누르는 사이 프롬프트가 꺼지면
-- (조합이 끝나 조합대가 바뀌거나 불이 꺼지면) 오지 않을 수 있어서, 여기서 직접 확인해 풀어 준다.
-- 안 풀면 고른 기구가 그 자리에 묶여 다른 기구(손님 자리·불난 와플 기계) 버튼이 영영 안 뜬다.
local function stillHolding(prompt: ProximityPrompt, root: BasePart): boolean
	local point = points[prompt]
	if not point or prompt:GetAttribute("On") ~= true then
		return false
	elseif os.clock() - heldAt > prompt.HoldDuration + 1 then
		return false
	elseif (point.WorldPosition - root.Position).Magnitude > REACH + 3 then
		return false
	end
	return touchHeld or UserInputService:IsKeyDown(prompt.KeyboardKeyCode) or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, prompt.GamepadKeyCode)
end

-- 바라보는 쪽의 가장 가까운 기구(프롬프트 자리)
local function choose(): Attachment?
	local character = player.Character
	local root = character and character.PrimaryPart
	if not root then
		return nil
	end
	local current = held
	if current then
		if stillHolding(current, root) then
			return points[current]
		end
		held = nil
	end
	local look = root.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	facing = if facing.Magnitude > 0.01 then facing.Unit else Vector3.new(0, 0, -1)
	local best: Attachment? = nil
	local bestScore = math.huge
	for prompt, point in points do
		if prompt:GetAttribute("On") == true then
			local offset = point.WorldPosition - root.Position
			offset = Vector3.new(offset.X, 0, offset.Z)
			local distance = offset.Magnitude
			if distance <= REACH then
				local dot = if distance > 0.05 then facing:Dot(offset.Unit) else 1
				local score = distance + (1 - dot) * TURN_COST
				if score < bestScore then
					best, bestScore = point, score
				end
			end
		end
	end
	return best
end

RunService.Heartbeat:Connect(function()
	local chosen = choose()
	local holdFactor = 1 - AnimalLooks.perksFor(player:GetAttribute("AnimalIndex")).hold
	for prompt, point in points do
		local want = point == chosen and prompt:GetAttribute("On") == true
		if prompt.Enabled ~= want then
			prompt.Enabled = want
		end
		local base = prompt:GetAttribute("Hold")
		if typeof(base) == "number" and base > 0 then
			local seconds = base * holdFactor
			if math.abs(prompt.HoldDuration - seconds) > 0.001 then
				prompt.HoldDuration = seconds
			end
		end
	end
end)

-- ── 알약 ──

local function bubbleFor(adornee: Instance): BillboardGui
	local existing = bubbles[adornee]
	if existing then
		return existing
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Prompt"
	gui.Adornee = adornee
	gui.AlwaysOnTop = true
	gui.Active = true
	gui.Size = UDim2.fromOffset(300, 64)
	gui.StudsOffset = Vector3.new(0, 1.8, 0)
	gui.LightInfluence = 0
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui
	gui.Parent = playerGui
	bubbles[adornee] = gui
	return gui
end

local function hide(prompt: ProximityPrompt)
	local entry = shown[prompt]
	if not entry then
		return
	end
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	entry.pill:Destroy()
	shown[prompt] = nil
	local gui = bubbles[entry.adornee]
	if gui and not gui:FindFirstChildWhichIsA("TextButton") then
		gui:Destroy()
		bubbles[entry.adornee] = nil
	end
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	hide(prompt)
	local adornee = prompt.Parent
	if not adornee then
		return
	end
	local isHold = prompt.HoldDuration > 0

	local pill = Instance.new("TextButton")
	pill.Text = ""
	pill.AutoButtonColor = false
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.fromOffset(0, 28)
	pill.BackgroundColor3 = PAPER
	pill.BorderSizePixel = 0
	pill.ClipsDescendants = true
	pill.LayoutOrder = if isHold then 2 else 1 -- E는 위, F(길게)는 아래
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Color = LINE
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = pill
	-- 길게 누를 때 차오르는 배경(목록 배치 밖에 두려고 row와 따로 둔다)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = SAGE
	fill.BackgroundTransparency = 0.55
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 1
	fill.Parent = pill

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Size = UDim2.fromOffset(0, 28)
	row.ZIndex = 2
	row.Parent = pill
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 3)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = row

	local key = Instance.new("TextLabel")
	key.Size = UDim2.fromOffset(22, 22)
	key.BackgroundColor3 = if isHold then SAGE else CORAL
	key.TextColor3 = Color3.new(1, 1, 1)
	key.Font = Enum.Font.GothamBold
	key.TextSize = 12
	key.Text = keyText(prompt, inputType)
	key.LayoutOrder = 1
	key.ZIndex = 2
	local keyRound = Instance.new("UICorner")
	keyRound.CornerRadius = UDim.new(1, 0)
	keyRound.Parent = key
	key.Parent = row

	local action = label(row, prompt.ActionText, 13, INK, 2)
	local object = label(row, prompt.ObjectText, 12, MUTED, 3)

	pill.Parent = bubbleFor(adornee)

	local connections = {
		prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
			action.Text = prompt.ActionText
		end),
		prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
			object.Text = prompt.ObjectText
		end),
		-- 터치·마우스: 알약을 누르는 동안 프롬프트를 누른 것으로 친다
		pill.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				touchHeld = true
				prompt:InputHoldBegin()
			end
		end),
		pill.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				touchHeld = false
				prompt:InputHoldEnd()
			end
		end),
	}
	shown[prompt] = { pill = pill, fill = fill, adornee = adornee, connections = connections }
end

ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	if prompt.Style == Enum.ProximityPromptStyle.Custom then
		show(prompt, inputType)
	end
end)

ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
	if held == prompt then
		held = nil
	end
	hide(prompt)
end)

-- 실행되면(길게 누르기 완료 포함) 고정을 푼다
ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
	if held == prompt then
		held = nil
	end
end)

ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt)
	if prompt.HoldDuration <= 0 then
		return
	end
	held = prompt
	heldAt = os.clock()
	local entry = shown[prompt]
	if entry and prompt.HoldDuration > 0 then
		entry.fill.Size = UDim2.fromScale(0, 1)
		local tween = TweenService:Create(entry.fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
		holding[prompt] = tween
		tween:Play()
	end
end)

ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
	if held == prompt then
		held = nil
	end
	local tween = holding[prompt]
	if tween then
		tween:Cancel()
		holding[prompt] = nil
	end
	local entry = shown[prompt]
	if entry then
		entry.fill.Size = UDim2.fromScale(0, 1)
	end
end)
