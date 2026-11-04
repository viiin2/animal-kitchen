--!strict
-- 손님 머리 위 주문 말풍선: 음식 그림(ViewportFrame) + 이름 + 인내심 막대.
-- 서버가 손님 모델에 단 속성(Orders JSON·Order·Group·OrderedAt·ExpiresAt·Mood)을 보고 그린다.
-- 아이스크림 주문은 그릇·맛·토핑까지 똑같이 그려서, 무엇을 만들지 그림으로 알 수 있다.
-- 단체 손님은 주문 그림이 여러 개 나란히 나오고, 낸 것은 흐려지며 ✓가 붙는다. 일행(Companion)은 말풍선이 없다.
-- 골치 아픈 손님은 속성 Note("급해요!"·"주문 바꿈!"·"떨어뜨렸어요!")를 이름 앞에 붉게 보여 준다.
-- 손님에게 내서 코인을 벌면 그 자리 위에 "+코인"이 떠오른다(Remotes.Earned).
-- 몸짓: 말풍선은 뽀용 튀어나오고, 인내심이 1/4 아래면 말풍선이 흔들리고 손님 이마에 💢(빡침)가 불끈불끈.
-- 화나서 나갈 때도 이마에 💢. 받으면 하트가 몽글몽글 떠오른다.
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local earnedEvent = remotes:WaitForChild(Config.Remotes.Earned) :: RemoteEvent

type Entry = { food: string, state: string, spec: Config.IceSpec?, done: boolean }

type Bubble = {
	gui: BillboardGui,
	card: Frame,
	pop: UIScale,
	vein: BillboardGui, -- 이마의 💢
	veinMark: TextLabel,
	feeling: string, -- 마지막으로 본 Mood
	cells: Frame,
	title: TextLabel,
	fill: Frame,
	mood: TextLabel,
	orders: string, -- 마지막으로 그린 Orders 속성
}

local INK = Color3.fromRGB(86, 66, 56)
local GOOD = Color3.fromRGB(120, 196, 120)
local WARN = Color3.fromRGB(246, 182, 86)
local BAD = Color3.fromRGB(230, 96, 84)
local GOLD = Color3.fromRGB(255, 190, 60)
local CORAL = Color3.fromRGB(236, 132, 100)

local CELL_STUDS = 2.7 -- 주문 그림 하나의 폭(스터드)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local folder = workspace:WaitForChild("Store"):WaitForChild("Customers")

local bubbles: { [Model]: Bubble } = {}

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(radius, 0)
	c.Parent = parent
end

local function parseOrders(text: unknown): { Entry }
	local entries: { Entry } = {}
	if typeof(text) ~= "string" then
		return entries
	end
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(text)
	end)
	if not ok or typeof(decoded) ~= "table" then
		return entries
	end
	for _, raw in decoded :: { any } do
		if typeof(raw) == "table" and typeof(raw.food) == "string" and typeof(raw.state) == "string" then
			table.insert(entries, {
				food = raw.food,
				state = raw.state,
				spec = if raw.spec ~= nil then Config.validIce(raw.spec) else nil,
				done = raw.done == true,
			})
		end
	end
	return entries
end

local function drawFood(view: ViewportFrame, kind: string, state: string, spec: Config.IceSpec?)
	local model = FoodModels.build(kind, state, 0, spec)
	local root = model.PrimaryPart :: BasePart
	model.Parent = view
	local reach = math.max(root.Size.X, root.Size.Z)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	camera.CFrame = CFrame.lookAt(Vector3.new(0, reach * 1.6, reach * 1.9), Vector3.new(0, 0, 0))
	camera.Parent = view
	view.CurrentCamera = camera
end

-- 주문 그림 칸을 다시 그린다. 칸 수만큼 말풍선이 넓어진다.
local function drawOrders(bubble: Bubble, entries: { Entry })
	bubble.cells:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bubble.cells
	local count = math.max(#entries, 1)
	bubble.gui.Size = UDim2.new(0.5 + CELL_STUDS * count, 0, 3.4, 0)
	for i, entry in entries do
		local view = Instance.new("ViewportFrame")
		view.BackgroundTransparency = 1
		view.Size = UDim2.fromScale(1 / count, 1)
		view.LayoutOrder = i
		view.Ambient = Color3.fromRGB(190, 180, 170)
		view.LightColor = Color3.fromRGB(255, 246, 236)
		view.LightDirection = Vector3.new(-1, -2, -1)
		view.ImageTransparency = if entry.done then 0.65 else 0
		view.Parent = bubble.cells
		drawFood(view, entry.food, entry.state, entry.spec)
		if entry.done then
			local check = Instance.new("TextLabel")
			check.BackgroundTransparency = 1
			check.Size = UDim2.fromScale(1, 1)
			check.Font = Enum.Font.FredokaOne
			check.TextScaled = true
			check.Text = "✓"
			check.TextColor3 = GOOD
			check.Parent = view
		end
	end
end

-- 받았을 때: 하트 세 개가 몽글몽글 떠올랐다 사라진다
local function floatHearts(root: BasePart)
	for i = 1, 3 do
		task.delay((i - 1) * 0.18, function()
			if not root.Parent then
				return
			end
			local gui = Instance.new("BillboardGui")
			gui.Adornee = root
			gui.Size = UDim2.new(1.3, 0, 1.3, 0)
			local x = (i - 2) * 1.1 + (math.random() - 0.5) * 0.4
			gui.StudsOffset = Vector3.new(x, 6.2, 0)
			gui.AlwaysOnTop = true
			gui.LightInfluence = 0
			local heart = Instance.new("TextLabel")
			heart.BackgroundTransparency = 1
			heart.Size = UDim2.fromScale(1, 1)
			heart.Font = Enum.Font.FredokaOne
			heart.TextScaled = true
			heart.Text = "♥"
			heart.TextColor3 = if i == 2 then Color3.fromRGB(255, 140, 170) else Color3.fromRGB(240, 110, 120)
			heart.Rotation = (math.random() - 0.5) * 30
			heart.Parent = gui
			gui.Parent = playerGui
			TweenService:Create(gui, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(x * 1.3, 9.5, 0) }):Play()
			task.delay(0.6, function()
				TweenService:Create(heart, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
			end)
			Debris:AddItem(gui, 1.3)
		end)
	end
end

local function make(model: Model)
	if model:GetAttribute("Companion") == true then
		return
	end
	local root = model:WaitForChild("Root", 5)
	if not root or not root:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "OrderBubble"
	gui.Adornee = root
	-- 크기를 스터드로 정해서 창 크기와 상관없이 손님 크기에 맞게 보인다
	gui.Size = UDim2.new(0.5 + CELL_STUDS, 0, 3.4, 0)
	gui.StudsOffset = Vector3.new(0, 7.9, 0) -- 토끼 귀 위
	gui.AlwaysOnTop = true
	gui.MaxDistance = 200
	gui.Enabled = false

	local card = Instance.new("Frame")
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Color3.fromRGB(255, 252, 246)
	card.BorderSizePixel = 0
	corner(card, 0.22)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(232, 214, 196)
	stroke.Thickness = 2
	stroke.Parent = card
	card.Parent = gui

	local cells = Instance.new("Frame")
	cells.BackgroundTransparency = 1
	cells.Size = UDim2.fromScale(0.92, 0.56)
	cells.Position = UDim2.fromScale(0.04, 0.03)
	cells.Parent = card

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(0.9, 0.17)
	title.Position = UDim2.fromScale(0.05, 0.6)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextWrapped = true
	title.TextColor3 = INK
	title.RichText = true
	title.Parent = card

	local back = Instance.new("Frame")
	back.BackgroundColor3 = Color3.fromRGB(238, 228, 216)
	back.BorderSizePixel = 0
	back.Size = UDim2.fromScale(0.8, 0.08)
	back.Position = UDim2.fromScale(0.1, 0.84)
	corner(back, 1)
	back.Parent = card
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = GOOD
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 1)
	corner(fill, 1)
	fill.Parent = back

	local mood = Instance.new("TextLabel")
	mood.BackgroundTransparency = 1
	mood.Size = UDim2.fromScale(1, 1)
	mood.Font = Enum.Font.FredokaOne
	mood.TextScaled = true
	mood.Visible = false
	mood.Parent = gui

	-- 뽀용: 말풍선(과 기분 글자)이 나타날 때 작게 시작해 통 튄다
	local pop = Instance.new("UIScale")
	pop.Parent = card
	local moodPop = Instance.new("UIScale")
	moodPop.Parent = mood
	-- 💢: 이마(머리 오른쪽 위)에 붙는다. 머리를 못 찾으면 발밑 기준으로 머리 높이에
	local head = model:WaitForChild("Head", 2)
	local vein = Instance.new("BillboardGui")
	vein.Name = "AngerVein"
	vein.Adornee = if head and head:IsA("BasePart") then head else root
	vein.Size = UDim2.new(1.4, 0, 1.4, 0)
	vein.StudsOffset = if head then Vector3.new(0.85, 0.85, 0) else Vector3.new(0.85, 4.5, 0)
	vein.AlwaysOnTop = true
	vein.LightInfluence = 0
	vein.Enabled = false
	local veinMark = Instance.new("TextLabel")
	veinMark.BackgroundTransparency = 1
	veinMark.AnchorPoint = Vector2.new(0.5, 0.5)
	veinMark.Position = UDim2.fromScale(0.5, 0.5)
	veinMark.Size = UDim2.fromScale(1, 1)
	veinMark.TextScaled = true
	veinMark.Text = "💢"
	veinMark.Parent = vein
	vein.Parent = playerGui

	gui.Parent = playerGui
	local bubble: Bubble = { gui = gui, card = card, pop = pop, vein = vein, veinMark = veinMark, feeling = "", cells = cells, title = title, fill = fill, mood = mood, orders = "" }
	bubbles[model] = bubble

	local function refresh()
		local ordersText = model:GetAttribute("Orders")
		local order = model:GetAttribute("Order")
		local feeling = model:GetAttribute("Mood")
		local entries = parseOrders(ordersText)
		if typeof(ordersText) == "string" and bubble.orders ~= ordersText then
			bubble.orders = ordersText
			drawOrders(bubble, entries)
		end
		if model:GetAttribute("Group") == true then
			local done = 0
			for _, entry in entries do
				if entry.done then
					done += 1
				end
			end
			title.Text = `단체 손님 {done}/{#entries}`
			title.TextColor3 = CORAL
		else
			local note = model:GetAttribute("Note")
			local name = if typeof(order) == "string" then order else ""
			title.Text = if typeof(note) == "string" then `<font color="#e0705a">{note}</font> {name}` else name
			title.TextColor3 = INK
		end
		if feeling == "happy" then
			card.Visible = false
			mood.Visible = true
			mood.Text = "♥"
			mood.TextColor3 = Color3.fromRGB(240, 110, 120)
		elseif feeling == "angry" then
			-- 화나서 나간다: 말풍선 대신 이마의 💢(RenderStepped)
			card.Visible = false
			mood.Visible = false
		elseif feeling == "table" then
			-- 받았는데 앉을 홀 테이블이 없다
			card.Visible = false
			mood.Visible = true
			mood.Text = "빈 테이블?"
			mood.TextColor3 = WARN
		else
			card.Visible = true
			mood.Visible = false
		end
		mood.Size = if feeling == "table" then UDim2.fromScale(1, 0.32) else UDim2.fromScale(1, 1)
		mood.Font = if feeling == "table" then Enum.Font.GothamBold else Enum.Font.FredokaOne
		gui.Enabled = feeling == "waiting" or feeling == "happy" or feeling == "angry" or feeling == "table"
		local now = if typeof(feeling) == "string" then feeling else ""
		if now ~= bubble.feeling then
			bubble.feeling = now
			-- 새 주문·기분이 바뀌면 뽀용
			local info = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			if card.Visible then
				pop.Scale = 0.3
				TweenService:Create(pop, info, { Scale = 1 }):Play()
			else
				moodPop.Scale = 0.2
				TweenService:Create(moodPop, info, { Scale = 1 }):Play()
			end
			if now == "happy" then
				floatHearts(root :: BasePart)
			end
		end
	end
	model.AttributeChanged:Connect(refresh)
	refresh()
end

local function remove(model: Model)
	local bubble = bubbles[model]
	if bubble then
		bubble.gui:Destroy()
		bubble.vein:Destroy()
		bubbles[model] = nil
	end
end

folder.ChildAdded:Connect(function(child: Instance)
	if child:IsA("Model") then
		make(child)
	end
end)
folder.ChildRemoved:Connect(function(child: Instance)
	if child:IsA("Model") then
		remove(child)
	end
end)
for _, child in folder:GetChildren() do
	if child:IsA("Model") then
		task.spawn(make, child)
	end
end

RunService.RenderStepped:Connect(function()
	local t = workspace:GetServerTimeNow()
	local clock = os.clock()
	for model, bubble in bubbles do
		local orderedAt = model:GetAttribute("OrderedAt")
		local expiresAt = model:GetAttribute("ExpiresAt")
		local hurry = false
		if typeof(orderedAt) == "number" and typeof(expiresAt) == "number" and expiresAt > orderedAt then
			local left = math.clamp((expiresAt - t) / (expiresAt - orderedAt), 0, 1)
			bubble.fill.Size = UDim2.fromScale(left, 1)
			bubble.fill.BackgroundColor3 = if left > 0.5 then GOOD elseif left > 0.25 then WARN else BAD
			hurry = left < 0.25 and bubble.feeling == "waiting"
		end
		-- 거의 다 기다렸으면 말풍선이 흔들리고, 이마에 💢가 불끈불끈(화나서 나갈 때도)
		bubble.card.Rotation = if hurry then math.sin(clock * 18) * 5 else 0
		local mad = hurry or bubble.feeling == "angry"
		bubble.vein.Enabled = mad
		if mad then
			local throb = 0.8 + 0.2 * math.abs(math.sin(clock * 7))
			bubble.veinMark.Size = UDim2.fromScale(throb, throb)
		end
	end
end)

-- ── 번 코인이 떠오른다 ──

earnedEvent.OnClientEvent:Connect(function(position: Vector3, amount: number, combo: number)
	local anchor = Instance.new("Attachment")
	anchor.Parent = workspace.Terrain
	anchor.WorldPosition = position
	local gui = Instance.new("BillboardGui")
	gui.Adornee = anchor
	gui.Size = UDim2.new(5, 0, 2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local labels: { TextLabel } = {}
	local function line(text: string, color: Color3, y: number, height: number)
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0, y)
		label.Size = UDim2.fromScale(1, height)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = color
		label.TextStrokeColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0
		label.Parent = gui
		table.insert(labels, label)
	end
	line(`+{amount} 코인`, GOLD, 0, 0.62)
	if combo > 0 then
		line(`팀 콤보 x{combo + 1}!`, CORAL, 0.62, 0.38)
	end
	gui.Parent = playerGui
	TweenService:Create(gui, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 3, 0) }):Play()
	task.delay(0.8, function()
		for _, label in labels do
			TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
	Debris:AddItem(gui, 1.6)
	Debris:AddItem(anchor, 1.6)
end)
