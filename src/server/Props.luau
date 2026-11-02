--!strict
-- 카페 기구 모델: 조리대·조합대·와플 기계·티 냄비·오븐·토핑대·재료 상자·아이스크림 기계·쟁반 더미·쓰레기통·소화기 받침.
-- at은 바닥 가운데 CFrame이고, LookVector 쪽이 앞(플레이어가 서는 쪽)이다. 모두 고정 파트다.
-- 색: 연분홍·연하늘 파스텔, 흰 수납장, 분홍 대리석 상판, 금색 손잡이(아기자기한 디저트 카페).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Build = require(ReplicatedStorage.Shared.Build)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)
local Config = require(ReplicatedStorage.Shared.Config)

export type Built = {
	model: Model,
	base: BasePart, -- 프롬프트를 붙이는 파트
	slots: { CFrame }, -- 물건을 올리는 면. 첫 칸이 가운데
	prompt: Vector3?, -- 프롬프트 위치(없으면 첫 칸이나 base 위). 뒷줄 기구는 앞쪽으로 당겨서 옆 기구보다 가깝게 잡히게 한다
	cover: BasePart?, -- 잠겼을 때 보이는 덮개
	tag: SurfaceGui?, -- 재료 상자 이름표(잠겼을 때는 숨긴다)
	steam: Smoke?, -- 티 냄비: 끓을 때 켠다
}

local Props = {}

Props.TOP = 3.5 -- 작업대 높이

local TOP = Props.TOP
local BLOCK = Enum.PartType.Block
local CYL = Enum.PartType.Cylinder

Props.PINK = Color3.fromRGB(250, 196, 212)
Props.PINK_DEEP = Color3.fromRGB(242, 150, 180)
Props.SKY = Color3.fromRGB(196, 228, 248)
Props.SKY_DEEP = Color3.fromRGB(150, 202, 238)
Props.WHITE = Color3.fromRGB(255, 251, 250)
Props.BUTTER = Color3.fromRGB(255, 236, 180)
Props.MINT = Color3.fromRGB(190, 236, 214)

local PINK, PINK_DEEP, SKY, SKY_DEEP, WHITE = Props.PINK, Props.PINK_DEEP, Props.SKY, Props.SKY_DEEP, Props.WHITE
local TOP_COLOR = Color3.fromRGB(252, 228, 236)
local KNOB = Color3.fromRGB(232, 190, 104)

local function model(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	return m
end

-- 수납장 + 상판. 상판 파트를 돌려준다(윗면 높이 = TOP).
-- 상판은 옆·뒤로 튀어나오지 않게 한다: 나란히 붙은 수납장끼리 상판이 겹치면 같은 높이의 면이 겹쳐 접합부가 우글우글 깜빡인다.
-- 앞으로만 0.1 내민다. 대리석 무늬도 멀리서 물결처럼 일렁여서 매끈한 재질을 쓴다.
local function cabinet(parent: Model, at: CFrame, width: number, depth: number, body: Color3, door: Color3): Part
	local h = TOP - 0.3
	Build.part(parent, BLOCK, Vector3.new(width, h, depth), at * CFrame.new(0, h / 2, 0), body)
	-- 걸레받이: 앞면을 몸통 앞면보다 살짝 앞으로(같은 자리면 두 면이 겹쳐 지글거린다)
	Build.part(parent, BLOCK, Vector3.new(width - 0.2, 0.3, depth - 0.2), at * CFrame.new(0, 0.15, -0.13), Build.shade(door, 0.15))
	local doorWidth = (width - 0.6) / 2
	for _, side in { -1, 1 } do
		local x = side * (doorWidth / 2 + 0.1)
		Build.part(parent, BLOCK, Vector3.new(doorWidth, h - 0.9, 0.06), at * CFrame.new(x, h / 2 + 0.1, -depth / 2 - 0.03), door)
		Build.ball(parent, 0.2, at * CFrame.new(side * 0.25, h / 2 + 0.4, -depth / 2 - 0.1), KNOB)
	end
	return Build.part(parent, BLOCK, Vector3.new(width, 0.3, depth + 0.1), at * CFrame.new(0, TOP - 0.15, -0.05), TOP_COLOR)
end

local function surface(at: CFrame, x: number, y: number, z: number): CFrame
	return at * CFrame.new(x, y, z)
end

-- 프롬프트 자리: 작업대 앞면 가운데(플레이어가 서서 바라보는 곳). 클라이언트(Prompts)는 바라보는 쪽의 가장 가까운 자리를 고른다.
local function front(at: CFrame, depth: number?): Vector3
	return (at * CFrame.new(0, TOP + 0.4, -(depth or 2) + 0.2)).Position
end
Props.front = front

function Props.counter(at: CFrame): Built
	local m = model("Counter")
	local top = cabinet(m, at, 4, 4, WHITE, SKY)
	return { model = m, base = top, slots = { surface(at, 0, TOP, 0) }, prompt = front(at) }
end

-- 조합대: 하늘색 매트 위에 재료를 세 개까지 올린다
function Props.board(at: CFrame): Built
	local m = model("Mixer")
	cabinet(m, at, 4, 4, WHITE, PINK)
	local mat = Build.part(m, BLOCK, Vector3.new(3.4, 0.12, 2.5), at * CFrame.new(0, TOP + 0.06, 0.1), SKY)
	Build.disc(m, 0.7, 0.4, at * CFrame.new(1.5, TOP + 0.2, 1.4), WHITE)
	Build.part(m, CYL, Vector3.new(0.8, 0.08, 0.08), at * CFrame.new(1.5, TOP + 0.55, 1.4) * CFrame.Angles(0, 0, math.rad(60)), Color3.fromRGB(214, 218, 226))
	local y = TOP + 0.12
	return { model = m, base = mat, slots = { surface(at, 0, y, 0), surface(at, -1.05, y, -0.2), surface(at, 1.05, y, -0.2) }, prompt = front(at) }
end

-- 와플 기계: 분홍 몸통, 뚜껑이 열린 와플 판
function Props.grill(at: CFrame): Built
	local m = model("WaffleMaker")
	cabinet(m, at, 4, 4, WHITE, PINK)
	local base = Build.part(m, BLOCK, Vector3.new(3.2, 0.5, 2.6), at * CFrame.new(0, TOP + 0.25, -0.1), PINK_DEEP)
	Build.part(m, BLOCK, Vector3.new(2.6, 0.08, 2.0), at * CFrame.new(0, TOP + 0.54, -0.1), Color3.fromRGB(196, 146, 86), Enum.Material.Metal)
	for i = -2, 2 do
		Build.part(m, BLOCK, Vector3.new(2.6, 0.05, 0.08), at * CFrame.new(0, TOP + 0.6, -0.1 + i * 0.4), Color3.fromRGB(166, 118, 64))
		Build.part(m, BLOCK, Vector3.new(0.08, 0.05, 2.0), at * CFrame.new(i * 0.55, TOP + 0.6, -0.1), Color3.fromRGB(166, 118, 64))
	end
	-- 뒤로 젖힌 뚜껑
	Build.part(m, BLOCK, Vector3.new(3.2, 0.4, 2.4), at * CFrame.new(0, TOP + 1.5, 1.45) * CFrame.Angles(math.rad(-70), 0, 0), PINK)
	local lamp = Build.ball(m, 0.22, at * CFrame.new(1.3, TOP + 0.3, -1.42), Color3.fromRGB(255, 120, 120), Enum.Material.Neon)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 170, 120)
	glow.Range = 5
	glow.Brightness = 0.6
	glow.Parent = lamp
	return { model = m, base = base, slots = { surface(at, 0, TOP + 0.62, -0.1) }, prompt = front(at) }
end

-- 티 냄비: 하늘색 법랑 냄비, 끓을 때 김이 난다. 넣은 음료는 윗부분만 보인다
function Props.pot(at: CFrame): Built
	local m = model("TeaPot")
	cabinet(m, at, 4, 4, WHITE, SKY)
	Build.disc(m, 2.6, 0.12, at * CFrame.new(0, TOP + 0.06, 0), Color3.fromRGB(90, 90, 100), Enum.Material.Metal)
	local body = Build.disc(m, 2.8, 1.3, at * CFrame.new(0, TOP + 0.77, 0), SKY_DEEP, Enum.Material.SmoothPlastic, 0.05)
	Build.disc(m, 2.86, 0.14, at * CFrame.new(0, TOP + 1.38, 0), WHITE)
	for i = 1, 6 do
		local angle = i * math.pi / 3
		Build.ball(m, 0.3, at * CFrame.new(math.cos(angle) * 1.36, TOP + 0.75, math.sin(angle) * 1.36), WHITE)
	end
	for _, side in { -1, 1 } do
		Build.part(m, BLOCK, Vector3.new(0.5, 0.16, 0.34), at * CFrame.new(side * 1.55, TOP + 1.15, 0), WHITE)
	end
	local steam = Instance.new("Smoke")
	steam.Color = Color3.fromRGB(255, 255, 255)
	steam.Opacity = 0.12
	steam.RiseVelocity = 3
	steam.Size = 1.2
	steam.Enabled = false
	steam.Parent = body
	local y = TOP + 0.5
	return { model = m, base = body, slots = { surface(at, 0, y, 0) }, steam = steam, prompt = front(at) }
end

-- 오븐: 분홍 오븐 앞에 구운 케이크를 꺼내 둔다
function Props.oven(at: CFrame): Built
	local m = model("Oven")
	local top = cabinet(m, at, 4, 4, WHITE, PINK)
	Build.part(m, BLOCK, Vector3.new(3.6, 2.2, 2.0), at * CFrame.new(0, TOP + 1.1, 0.95), PINK_DEEP)
	local window = Build.disc(m, 1.3, 0.1, at * CFrame.new(0, TOP + 1.1, -0.06) * CFrame.Angles(math.rad(90), 0, 0), Color3.fromRGB(255, 190, 120), Enum.Material.Neon)
	window.Transparency = 0.2
	Build.part(m, CYL, Vector3.new(0.14, 1.5, 1.5), at * CFrame.new(0, TOP + 1.1, -0.04) * CFrame.Angles(0, math.rad(90), 0), WHITE)
	for _, x in { -1.3, 1.3 } do
		Build.part(m, CYL, Vector3.new(0.15, 0.3, 0.3), at * CFrame.new(x, TOP + 1.8, -0.08) * CFrame.Angles(0, math.rad(90), 0), WHITE)
	end
	return { model = m, base = top, slots = { surface(at, 0, TOP, -1.0) }, prompt = front(at) }
end

-- 토핑대: 생크림·딸기 시럽·초코 시럽 병과 스프링클 병
function Props.sauce(at: CFrame): Built
	local m = model("Topping")
	local top = cabinet(m, at, 4, 4, WHITE, SKY)
	for i, c in { WHITE, Color3.fromRGB(246, 120, 160), Color3.fromRGB(120, 76, 56) } do
		local x = -1.5 + (i - 1) * 0.55
		Build.disc(m, 0.45, 1.0, at * CFrame.new(x, TOP + 0.5, 1.2), c)
		Build.disc(m, 0.18, 0.3, at * CFrame.new(x, TOP + 1.15, 1.2), Color3.fromRGB(240, 240, 244))
	end
	local jar = Build.disc(m, 0.7, 0.8, at * CFrame.new(1.3, TOP + 0.4, 1.2), Color3.fromRGB(236, 246, 255))
	jar.Transparency = 0.35
	for i = 1, 5 do
		Build.ball(m, 0.14, at * CFrame.new(1.3 + math.cos(i) * 0.15, TOP + 0.2 + i * 0.1, 1.2 + math.sin(i) * 0.15), ({ PINK_DEEP, SKY_DEEP, Props.BUTTER, Props.MINT })[i % 4 + 1])
	end
	return { model = m, base = top, slots = { surface(at, 0, TOP, -0.7) }, prompt = front(at) }
end

-- 재료 상자: 파스텔 나무 상자 위에 그 재료를 크게 올려 둬서 멀리서도 무엇인지 보인다
function Props.crate(at: CFrame, ingredient: string, tint: Color3, facing: Vector3): Built
	local m = model("Crate")
	local h = TOP - 0.1
	local box = Build.part(m, BLOCK, Vector3.new(3.8, h, 3.8), at * CFrame.new(0, h / 2, 0), tint, Enum.Material.WoodPlanks)
	for _, y in { 0.5, h - 0.25 } do
		Build.part(m, BLOCK, Vector3.new(4.0, 0.4, 4.0), at * CFrame.new(0, y, 0), WHITE, Enum.Material.WoodPlanks)
	end
	Build.part(m, BLOCK, Vector3.new(3.4, 0.1, 3.4), at * CFrame.new(0, h + 0.05, 0), WHITE)
	local display = FoodModels.build(ingredient, "raw")
	display:ScaleTo(1.6)
	local root = display.PrimaryPart :: BasePart
	display:PivotTo(at * CFrame.new(0, h + 0.1 + root.Size.Y / 2, 0))
	display.Parent = m
	-- 이름표: 상자 뒤쪽 위에 세워 카메라 쪽을 보게 한다(상자가 다섯 개라 그림만으로는 헷갈린다).
	-- 모든 상자가 같은 방향(facing)을 봐야 기울기가 똑같다(상자마다 카메라를 보게 하면 제각각 삐뚤어 보였다)
	local spot = (at * CFrame.new(0, h + 0.5, 1.45)).Position
	local plate = Build.part(m, BLOCK, Vector3.new(2.6, 0.8, 0.05), CFrame.lookAt(spot, spot + facing), WHITE)
	plate.Transparency = 1
	local tag = Instance.new("SurfaceGui")
	tag.Face = Enum.NormalId.Front
	tag.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	tag.PixelsPerStud = 60
	tag.LightInfluence = 0.2
	local card = Instance.new("TextLabel")
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = WHITE
	card.Text = Config.Ingredients[ingredient].name
	card.TextScaled = true
	card.Font = Enum.Font.GothamBold
	card.TextColor3 = Color3.fromRGB(150, 96, 116)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.4, 0)
	round.Parent = card
	local border = Instance.new("UIStroke")
	border.Color = PINK_DEEP
	border.Thickness = 4
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = card
	local inset = Instance.new("UIPadding")
	inset.PaddingTop = UDim.new(0.12, 0)
	inset.PaddingBottom = UDim.new(0.12, 0)
	inset.Parent = card
	card.Parent = tag
	tag.Parent = plate
	-- 잠긴 상자는 천을 덮어 재료를 가린다
	local cover = Build.part(m, BLOCK, Vector3.new(4.1, 1.8, 4.1), at * CFrame.new(0, h + 0.9, 0), Color3.fromRGB(240, 226, 232))
	cover.Transparency = 1
	return { model = m, base = box, slots = {}, prompt = (at * CFrame.new(0, h, -1.6)).Position, cover = cover, tag = tag }
end

-- 아이스크림 기계: 흰 몸통에 맛별 노즐 네 개, 위에는 큰 아이스크림 장식
-- promptX: 프롬프트를 가운데에서 옆(기계 기준 x)으로 옮긴다(기계 한쪽이 옆 기구 줄 뒤에 들어가 있을 때 통로 쪽으로)
function Props.iceMachine(at: CFrame, promptX: number?): Built
	local m = model("IceCreamMachine")
	cabinet(m, at, 6, 4, WHITE, PINK)
	local body = Build.part(m, BLOCK, Vector3.new(5.4, 2.6, 2.6), at * CFrame.new(0, TOP + 1.3, 0.5), WHITE)
	Build.part(m, BLOCK, Vector3.new(5.5, 0.5, 2.7), at * CFrame.new(0, TOP + 2.4, 0.5), PINK_DEEP)
	Build.part(m, BLOCK, Vector3.new(5.5, 0.3, 2.7), at * CFrame.new(0, TOP + 0.15, 0.5), SKY)
	for i, flavor in Config.IceCream.flavors do
		local x = -1.95 + (i - 1) * 1.3
		Build.disc(m, 0.55, 0.5, at * CFrame.new(x, TOP + 0.9, -0.95), flavor.color)
		Build.ball(m, 0.4, at * CFrame.new(x, TOP + 1.55, -0.85), flavor.color)
	end
	-- 큰 아이스크림 장식(간판 역할)
	local sign = FoodModels.build("icecream", "cooked", 0, { base = "cone", flavors = { "strawberry", "mint", "vanilla" }, topping = "cherry" })
	sign:ScaleTo(2.2)
	local root = sign.PrimaryPart :: BasePart
	sign:PivotTo(at * CFrame.new(0, TOP + 2.65 + root.Size.Y / 2, 0.6))
	sign.Parent = m
	return { model = m, base = body, slots = {}, prompt = (at * CFrame.new(promptX or 0, TOP + 0.6, -1.7)).Position }
end

-- 개수대: 하늘색 싱크볼, 금색 수도꼭지, 비누 거품. 빈 그릇을 세 개까지 넣고 F 길게로 설거지한다
function Props.sink(at: CFrame): Built
	local m = model("Sink")
	cabinet(m, at, 4, 4, WHITE, SKY)
	local basin = Build.part(m, BLOCK, Vector3.new(3.0, 0.2, 2.6), at * CFrame.new(0, TOP + 0.02, -0.1), SKY_DEEP)
	for _, z in { -1.4, 1.2 } do
		Build.part(m, BLOCK, Vector3.new(3.2, 0.25, 0.2), at * CFrame.new(0, TOP + 0.12, z), WHITE)
	end
	for _, x in { -1.5, 1.5 } do
		Build.part(m, BLOCK, Vector3.new(0.2, 0.25, 2.6), at * CFrame.new(x, TOP + 0.12, -0.1), WHITE)
	end
	Build.disc(m, 0.25, 1.0, at * CFrame.new(0, TOP + 0.5, 1.45), KNOB, Enum.Material.Metal)
	Build.part(m, CYL, Vector3.new(0.8, 0.2, 0.2), at * CFrame.new(0, TOP + 1.0, 1.1) * CFrame.Angles(0, math.rad(90), 0), KNOB, Enum.Material.Metal)
	for i = 1, 5 do
		Build.ball(m, 0.3 + (i % 2) * 0.15, at * CFrame.new(-1.2 + i * 0.4, TOP + 0.25, 0.7 - (i % 3) * 0.3), WHITE)
	end
	local y = TOP + 0.12
	return { model = m, base = basin, slots = { surface(at, -0.75, y, -0.3), surface(at, 0.75, y, -0.3), surface(at, 0, y, 0.4) }, prompt = front(at) }
end

function Props.plates(at: CFrame): Built
	local m = model("Trays")
	local top = cabinet(m, at, 4, 4, WHITE, PINK)
	for i = 0, 5 do
		local tray = FoodModels.build("plate", "")
		tray:PivotTo(at * CFrame.new(0, TOP + 0.1 + i * 0.16, 0))
		tray.Parent = m
	end
	return { model = m, base = top, slots = {}, prompt = (at * CFrame.new(0, TOP + 0.3, -1.6)).Position }
end

function Props.trash(at: CFrame): Built
	local m = model("Trash")
	Build.disc(m, 2.4, 3.0, at * CFrame.new(0, 1.5, 0), PINK)
	Build.disc(m, 2.5, 0.25, at * CFrame.new(0, 0.6, 0), WHITE)
	local lid = Build.disc(m, 2.55, 0.2, at * CFrame.new(0, 3.1, 0), WHITE)
	Build.ball(m, 0.45, at * CFrame.new(0, 3.3, 0), PINK_DEEP)
	return { model = m, base = lid, slots = {}, prompt = (at * CFrame.new(0, 3.6, -1.0)).Position }
end

function Props.extinguisher(at: CFrame): Built
	local m = model("ExtinguisherStand")
	Build.part(m, BLOCK, Vector3.new(1.6, 2.4, 1.6), at * CFrame.new(0, 1.2, 0), WHITE)
	Build.part(m, BLOCK, Vector3.new(1.62, 0.4, 1.62), at * CFrame.new(0, 1.6, 0), Color3.fromRGB(240, 110, 120))
	local top = Build.part(m, BLOCK, Vector3.new(1.8, 0.15, 1.8), at * CFrame.new(0, 2.475, 0), PINK)
	return { model = m, base = top, slots = { surface(at, 0, 2.55, 0) }, prompt = (at * CFrame.new(0, 3.1, -0.6)).Position }
end

return Props
