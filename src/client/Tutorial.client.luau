--!strict
-- 튜토리얼 안내: 서버가 튜토리얼(phase "tutorial", 연습 손님 Config.Tutorial)을 시작하면 왼쪽에 단계 카드를 띄우고,
-- 지금 가야 할 기구 위에 통통 튀는 ▼ 화살표를 단다. 단계는 플레이어 속성(Holding·Served·IceWindowOpen)을 보고 넘어간다.
-- 기구는 Store가 붙인 모델 이름·Kind 속성으로 찾고, 잠긴 기구(Locked)는 가리키지 않는다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Config)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stateEvent = remotes:WaitForChild(Config.Remotes.State) :: RemoteEvent
local tutorialEvent = remotes:WaitForChild(Config.Remotes.Tutorial) :: RemoteEvent

type Step = {
	text: string,
	targets: () -> { Instance },
	done: () -> boolean,
}

local BODY = Enum.Font.GothamBold
local ROUND = Enum.Font.FredokaOne
local INK = Color3.fromRGB(110, 76, 90)
local MUTED = Color3.fromRGB(168, 136, 150)
local PAPER = Color3.fromRGB(255, 248, 251)
local PINK = Color3.fromRGB(250, 196, 212)
local CORAL = Color3.fromRGB(236, 132, 100)
local WHITE = Color3.new(1, 1, 1)

-- 카드 크기는 직접 계산한다. AutomaticSize는 UIScale과 같이 쓰면 줄바꿈된 글의 높이를 한 줄로 잡아서 글이 잘렸다.
local CARD_W = 290
local PAD_X, PAD_Y, GAP = 16, 12, 8
local HEAD_H, SKIP_H = 24, 30
local TEXT_SIZE = 16
local LINE = 1.15

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local stationsFolder = workspace:WaitForChild("Store"):WaitForChild("Stations")

-- ── 화면 ──

local gui = Instance.new("ScreenGui")
gui.Name = "TutorialCard"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
gui.Enabled = false
gui.Parent = playerGui

local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0, 0.5)
card.Position = UDim2.new(0, 14, 0.42, 0)
card.Size = UDim2.fromOffset(CARD_W, 120)
card.BackgroundColor3 = PAPER
card.BorderSizePixel = 0
card.Parent = gui
local round = Instance.new("UICorner")
round.CornerRadius = UDim.new(0, 18)
round.Parent = card
local border = Instance.new("UIStroke")
border.Color = PINK
border.Thickness = 3
border.Parent = card
local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, PAD_X)
padding.PaddingRight = UDim.new(0, PAD_X)
padding.PaddingTop = UDim.new(0, PAD_Y)
padding.PaddingBottom = UDim.new(0, PAD_Y)
padding.Parent = card
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, GAP)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = card
local scale = Instance.new("UIScale")
scale.Parent = card

local heading = Instance.new("TextLabel")
heading.BackgroundTransparency = 1
heading.Size = UDim2.new(1, 0, 0, HEAD_H)
heading.Font = ROUND
heading.TextSize = 20
heading.TextColor3 = CORAL
heading.TextXAlignment = Enum.TextXAlignment.Left
heading.LayoutOrder = 1
heading.Parent = card

local body = Instance.new("TextLabel")
body.BackgroundTransparency = 1
body.Size = UDim2.new(1, 0, 0, TEXT_SIZE)
body.Font = BODY
body.TextSize = TEXT_SIZE
body.TextColor3 = INK
body.TextWrapped = true
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.LineHeight = LINE
body.LayoutOrder = 2
body.Parent = card

local skip = Instance.new("TextButton")
skip.Size = UDim2.fromOffset(96, SKIP_H)
skip.BackgroundColor3 = WHITE
skip.BorderSizePixel = 0
skip.Font = BODY
skip.TextSize = 13
skip.TextColor3 = MUTED
skip.Text = "건너뛰기"
skip.LayoutOrder = 3
skip.Parent = card
local skipRound = Instance.new("UICorner")
skipRound.CornerRadius = UDim.new(0, 10)
skipRound.Parent = skip
local skipBorder = Instance.new("UIStroke")
skipBorder.Color = PINK
skipBorder.Thickness = 2
skipBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
skipBorder.Parent = skip

-- 글 길이에 맞춰 본문과 카드 높이를 다시 잡는다(글을 바꿀 때마다 부른다)
local function fitCard()
	local bounds = TextService:GetTextSize(body.Text, TEXT_SIZE, BODY, Vector2.new(CARD_W - PAD_X * 2, 10000))
	local bodyH = math.ceil(math.max(bounds.Y, TEXT_SIZE) * LINE) + 4
	body.Size = UDim2.new(1, 0, 0, bodyH)
	local height = PAD_Y * 2 + HEAD_H + GAP + bodyH
	if skip.Visible then
		height += GAP + SKIP_H
	end
	card.Size = UDim2.fromOffset(CARD_W, height)
end
local skipped = false
skip.Activated:Connect(function()
	skipped = true
	tutorialEvent:FireServer(false)
end)

-- ── 화살표 ──

local arrows: { BillboardGui } = {}

local function clearArrows()
	for _, arrow in arrows do
		arrow:Destroy()
	end
	table.clear(arrows)
end

local function pointAt(targets: { Instance })
	clearArrows()
	for _, target in targets do
		local arrow = Instance.new("BillboardGui")
		arrow.Name = "TutorialArrow"
		arrow.Adornee = target
		arrow.Size = UDim2.new(1.6, 0, 1.6, 0)
		arrow.StudsOffset = Vector3.new(0, 3, 0)
		arrow.AlwaysOnTop = true
		arrow.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = BODY
		label.TextScaled = true
		label.Text = "▼"
		label.TextColor3 = CORAL
		label.TextStrokeColor3 = WHITE
		label.TextStrokeTransparency = 0
		label.Parent = arrow
		arrow.Parent = playerGui
		table.insert(arrows, arrow)
	end
end

-- 열린 기구의 프롬프트 위치(Kind와 이름으로 찾는다)
local function stations(kind: string, name: string?): () -> { Instance }
	return function()
		local found = {}
		for _, model in stationsFolder:GetChildren() do
			if model:GetAttribute("Kind") == kind and (name == nil or model.Name == name) and model:GetAttribute("Locked") ~= true then
				local point = model:FindFirstChild("PromptPoint", true)
				if point then
					table.insert(found, point)
				end
			end
		end
		return found
	end
end

local function nothing(): { Instance }
	return {}
end

local function holding(): string?
	local value = player:GetAttribute("Holding")
	return if typeof(value) == "string" then value else nil
end

local function served(): number
	local value = player:GetAttribute("Served")
	return if typeof(value) == "number" then value else 0
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character.PrimaryPart
	return if root then root.Position else nil
end

-- ── 단계 ──

local firstIce = Config.Tutorial[1].spec
local iceName = if firstIce then Config.iceName(firstIce) else "아이스크림"
local milkTea = Config.Dishes.milk_tea.name
local seat = stations("seat", "3번 손님")

local startAt: Vector3? = nil
local servedAtStep = 0
local broughtTea = false
local broughtMilk = false
local stepHand: string? = nil

local steps: { Step } = {
	{
		text = "WASD(휴대폰은 왼쪽 조이스틱)로 걸어 보세요.",
		targets = nothing,
		done = function()
			local here, from = rootPosition(), startAt
			return here ~= nil and from ~= nil and (here - from).Magnitude > 4
		end,
	},
	{
		text = "첫 손님이 왔어요! 뒷줄 양 끝의 아이스크림 기계(아무 쪽이나)로 가서 E를 눌러요.",
		targets = stations("icemachine"),
		done = function()
			return player:GetAttribute("IceWindowOpen") == true
		end,
	},
	{
		text = `말풍선과 똑같이 만들어요: {iceName}\n그릇 → 맛 → 완성! 창을 닫았다면 기계에서 다시 E.`,
		targets = function()
			return if player:GetAttribute("IceWindowOpen") == true then {} else stations("icemachine")()
		end,
		done = function()
			local hand = holding()
			return hand ~= nil and (string.find(hand, "콘", 1, true) ~= nil or string.find(hand, "컵", 1, true) ~= nil)
		end,
	},
	{
		text = "든 채로 가운데 손님 앞 자리에서 E! 아이스크림·음료는 쟁반 없이 바로 내요.",
		targets = seat,
		done = function()
			return served() > servedAtStep
		end,
	},
	{
		-- 찻잎·우유는 어느 쪽을 먼저 올려도 된다(조합대는 재료 순서를 보지 않는다)
		text = `다음 손님은 {milkTea}! 찻잎과 우유를 하나씩 꺼내 같은 조합대(하늘색 매트)에 E로 올려요. 순서는 상관없어요.`,
		targets = function()
			local hand = holding()
			if hand == "찻잎" or hand == "우유" then
				return stations("board")()
			end
			local found = {}
			for _, item in { { brought = broughtTea, name = "찻잎" }, { brought = broughtMilk, name = "우유" } } do
				if not item.brought then
					for _, point in stations("crate", item.name)() do
						table.insert(found, point)
					end
				end
			end
			return found
		end,
		done = function()
			local hand = holding()
			if stepHand == "찻잎" and hand == nil then
				broughtTea = true
			elseif stepHand == "우유" and hand == nil then
				broughtMilk = true
			end
			stepHand = hand
			return broughtTea and broughtMilk
		end,
	},
	{
		text = "조합대에서 F를 길게 눌러 섞은 뒤, E로 집어요.",
		targets = stations("board"),
		done = function()
			local hand = holding()
			return hand ~= nil and string.find(hand, milkTea, 1, true) ~= nil
		end,
	},
	{
		text = "오른쪽 벽 티 냄비에 E로 올려요. 막대가 주황이 되면 E로 집어요(빨강이 되면 타요!).",
		targets = stations("pot"),
		done = function()
			return holding() == milkTea
		end,
	},
	{
		text = `{milkTea}를 손님에게 내요!`,
		targets = seat,
		done = function()
			return served() > servedAtStep
		end,
	},
}

local current = 0
local running = false
local lastHolding: string? = nil
local lastWindow = false

local function enter(index: number)
	current = index
	local step = steps[index]
	if not step then
		heading.Text = "튜토리얼 끝!"
		body.Text = "잘했어요! 이제 준비 화면에서 영업을 시작해 봐요."
		skip.Visible = false
		fitCard()
		clearArrows()
		return
	end
	startAt = rootPosition()
	servedAtStep = served()
	broughtTea, broughtMilk = false, false
	stepHand = holding()
	heading.Text = `튜토리얼 {index}/{#steps}`
	body.Text = step.text
	skip.Visible = true
	fitCard()
	pointAt(step.targets())
end

local function applyScale()
	local camera = workspace.CurrentCamera
	if camera then
		local size = camera.ViewportSize
		scale.Scale = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.6, 1)
	end
end

local function begin()
	running = true
	skipped = false
	gui.Enabled = true
	applyScale()
	lastHolding = holding()
	enter(1)
end

local function finish()
	running = false
	clearArrows()
	if current > #steps then
		-- 마지막 칭찬 카드는 잠깐 더 보여 준다
		task.delay(3, function()
			if not running then
				gui.Enabled = false
			end
		end)
	else
		gui.Enabled = false
	end
end

stateEvent.OnClientEvent:Connect(function(incoming: { phase: string })
	local inTutorial = incoming.phase == "tutorial"
	if inTutorial and not running then
		begin()
	elseif not inTutorial and running then
		if not skipped and current <= #steps and current > 0 then
			-- 서버가 먼저 끝냈다(연습 손님을 다 받음)면 마지막 카드로
			enter(#steps + 1)
		end
		finish()
	end
end)

RunService.Heartbeat:Connect(function()
	if not running then
		return
	end
	local step = steps[current]
	if not step then
		return
	end
	if step.done() then
		enter(current + 1)
		return
	end
	-- 손에 든 것이 바뀌면 화살표 대상도 다시 고른다(우유 → 조합대 등)
	local hand = holding()
	local window = player:GetAttribute("IceWindowOpen") == true
	if hand ~= lastHolding or window ~= lastWindow then
		lastHolding = hand
		lastWindow = window
		pointAt(step.targets())
	end
end)

-- 화살표가 통통 튄다
RunService.RenderStepped:Connect(function()
	if #arrows == 0 then
		return
	end
	local lift = 3 + math.abs(math.sin(os.clock() * 4)) * 0.8
	for _, arrow in arrows do
		arrow.StudsOffset = Vector3.new(0, lift, 0)
	end
end)
