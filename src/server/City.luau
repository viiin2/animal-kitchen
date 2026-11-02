--!strict
-- 가게 밖 도시: 가게가 선 블록(인도)을 차도가 둘러싸고, 길 건너에 파스텔 건물이 늘어선다.
--   가게 블록 인도 x -44~44, z -44~32 → 차도(폭 16, 앞·뒤 길은 도시 끝까지) → 길 건너 인도 → 건물
-- 전체 보기 카메라는 주방 뒤 위에서 앞(-Z)을 보므로 앞쪽 건물들이 화면 위쪽 배경이 된다.
-- 손님은 가게 양옆 문 앞(x ±31, z -14)에서 나타나고 사라지므로 그 길목(z -20~-8)에는 아무것도 두지 않는다.
-- 시간 흐름(아침 → 노을 → 밤)은 각자 화면에서 Outdoor.client가 도시 파트 색과 불빛으로 보여 준다(가게 안 조명은 그대로).
-- 그래서 해 질 녘에 켤 가로등 전구(속성 StreetLamp)와 창문(속성 LitAtNight)에 표시만 해 둔다. 건물은 그림자를 끈다(가볍게).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Build = require(ReplicatedStorage.Shared.Build)

local BLOCK = Enum.PartType.Block
local CYL = Enum.PartType.Cylinder
local WHITE = Color3.fromRGB(255, 255, 255)
local ROAD = Color3.fromRGB(118, 122, 136)
local WALK = Color3.fromRGB(228, 226, 234)
local LOT = Color3.fromRGB(214, 214, 224)
local LINE = Color3.fromRGB(248, 248, 252)
local POLE = Color3.fromRGB(96, 104, 122)
local WINDOW_DAY = Color3.fromRGB(196, 226, 248)

local GROUND = -0.05 -- 인도 윗면(가게 바닥 0보다 살짝 아래)
local ASPHALT = -0.6 -- 차도 윗면(인도와 턱이 진다)
local FAR = 112 -- 도시 끝

-- 가게 블록과 그 둘레 차도(폭 16)
local SHOP_X = 44
local SHOP_FRONT, SHOP_BACK = -44, 32
local ROAD_W = 16

-- 건물 색(노랑은 빼서 화면이 누렇게 보이지 않게)과 1층 가게 차양 색
local COLORS = {
	Color3.fromRGB(250, 212, 200), -- 복숭아
	Color3.fromRGB(198, 222, 244), -- 하늘
	Color3.fromRGB(208, 234, 216), -- 민트
	Color3.fromRGB(228, 216, 246), -- 라벤더
	Color3.fromRGB(246, 206, 220), -- 분홍
	Color3.fromRGB(232, 234, 240), -- 밝은 회색
	Color3.fromRGB(186, 206, 228), -- 푸른 회색
	Color3.fromRGB(240, 224, 214), -- 모래
}
local AWNINGS = {
	Color3.fromRGB(236, 120, 150),
	Color3.fromRGB(110, 170, 226),
	Color3.fromRGB(110, 190, 150),
	Color3.fromRGB(170, 140, 220),
	Color3.fromRGB(240, 150, 110),
}
local SHOPS = { "꽃집", "빵집", "서점", "문구점", "편의점", "미용실", "장난감 가게", "카페", "약국", "세탁소", "옷가게", "음반 가게", "사진관", "분식집", "과일 가게", "인형 가게" }

local City = {}

local function part(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Build.part(parent, BLOCK, size, cframe, color, material)
	p.CastShadow = false
	return p
end

-- 세운 원기둥(지름, 높이)
local function pillar(parent: Instance, diameter: number, height: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Build.disc(parent, diameter, height, cframe, color, material)
	p.CastShadow = false
	return p
end

local function ball(parent: Instance, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Build.ball(parent, diameter, cframe, color, material)
	p.CastShadow = false
	return p
end

-- 땅 한 판(x0~x1, z0~z1, 윗면 높이 top, 두께 1). 서로 겹치지 않게 놓는다(겹치면 깜빡인다).
local function slab(parent: Instance, x0: number, x1: number, z0: number, z1: number, top: number, color: Color3, material: Enum.Material)
	local p = part(parent, Vector3.new(x1 - x0, 1, z1 - z0), CFrame.new((x0 + x1) / 2, top - 0.5, (z0 + z1) / 2), color, material)
	p.Name = "Ground"
end

-- 차도 위 흰 칠(두께 0.04)
local function paint(parent: Instance, size: Vector3, cframe: CFrame)
	part(parent, Vector3.new(size.X, 0.04, size.Z), cframe + Vector3.new(0, ASPHALT + 0.02, 0), LINE)
end

-- 가운데 점선: from에서 to까지 6칸마다 3칸짜리
local function dashes(parent: Instance, from: Vector3, to: Vector3, skip: ((Vector3) -> boolean)?)
	local dir = (to - from).Unit
	local length = (to - from).Magnitude
	for d = 0, length - 3, 6 do
		local p = from + dir * (d + 1.5)
		if not (skip and skip(p)) then
			paint(parent, Vector3.new(0.35, 0, 3), CFrame.lookAt(p, p + dir))
		end
	end
end

-- 횡단보도: center에서 walk 방향(차도를 건너는 쪽)으로 줄무늬를 깐다. 줄은 차가 다니는 방향으로 길다.
local function crosswalk(parent: Instance, center: Vector3, walk: Vector3)
	local frame = CFrame.lookAt(center, center + walk)
	local count = math.floor(ROAD_W / 1.8)
	for i = 0, count - 1 do
		local offset = (i - (count - 1) / 2) * 1.8
		paint(parent, Vector3.new(5, 0, 0.9), frame * CFrame.new(0, 0, offset))
	end
end

-- 건물 하나. at은 앞면 가운데 바닥, LookVector는 길 쪽(앞). 1층은 가게(유리창·줄무늬 차양·간판), 위층은 창문.
local function building(parent: Instance, at: CFrame, width: number, depth: number, height: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Building"
	model.Parent = parent
	local color = COLORS[rng:NextInteger(1, #COLORS)]
	local accent = AWNINGS[rng:NextInteger(1, #AWNINGS)]
	part(model, Vector3.new(width, height, depth), at * CFrame.new(0, height / 2, depth / 2), color)
	-- 옥상 테두리와 1층·2층 사이 띠
	part(model, Vector3.new(width + 0.4, 0.6, depth + 0.4), at * CFrame.new(0, height + 0.3, depth / 2), Build.shade(color, 0.08))
	part(model, Vector3.new(width + 0.2, 0.4, 0.3), at * CFrame.new(0, 6.6, -0.1), WHITE)

	-- 1층 가게
	local glass = part(model, Vector3.new(width - 3, 3.4, 0.12), at * CFrame.new(0, 1.9, -0.06), WINDOW_DAY)
	glass.Reflectance = 0.15
	local span = width - 2
	local stripes = math.max(2, math.floor(span / 2))
	local stripe = span / stripes
	for i = 0, stripes - 1 do
		local x = -span / 2 + (i + 0.5) * stripe
		part(model, Vector3.new(stripe, 0.15, 2.2), at * CFrame.new(x, 4.1, -1.0) * CFrame.Angles(math.rad(-20), 0, 0), if i % 2 == 0 then accent else WHITE)
	end
	local sign = part(model, Vector3.new(math.min(width - 4, 10), 1.3, 0.2), at * CFrame.new(0, 5.4, -0.12), WHITE)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.3
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = SHOPS[rng:NextInteger(1, #SHOPS)]
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = Build.shade(accent, 0.15)
	label.Parent = gui
	gui.Parent = sign

	-- 위층 창문(층 높이 4). 일부는 해 질 녘부터 불이 들어온다(Outdoor.client).
	local floors = math.max(0, math.floor((height - 10.5) / 4) + 1)
	local cols = math.max(1, math.floor((width - 2) / 4))
	for f = 0, floors - 1 do
		for c = 0, cols - 1 do
			local x = (c - (cols - 1) / 2) * 4
			local window = part(model, Vector3.new(2.4, 2.4, 0.12), at * CFrame.new(x, 9 + f * 4, -0.06), WINDOW_DAY)
			window.Reflectance = 0.15
			part(model, Vector3.new(2.8, 0.2, 0.3), at * CFrame.new(x, 7.7 + f * 4, -0.12), WHITE)
			if rng:NextNumber() < 0.55 then
				window:SetAttribute("LitAtNight", true)
			end
		end
	end

	-- 옥상: 물탱크나 실외기
	local roofX = rng:NextNumber(-width / 4, width / 4)
	if rng:NextNumber() < 0.5 then
		pillar(model, 3, 2.6, at * CFrame.new(roofX, height + 1.9, depth / 2), Color3.fromRGB(150, 196, 230))
		pillar(model, 3.2, 0.3, at * CFrame.new(roofX, height + 3.3, depth / 2), WHITE)
	else
		part(model, Vector3.new(3, 1.6, 2.4), at * CFrame.new(roofX, height + 1.4, depth / 2), Color3.fromRGB(214, 218, 226))
	end
end

-- 한 줄로 건물을 세운다. origin은 줄의 시작(앞면 바닥), along은 줄을 따라가는 방향, facing은 건물 앞(길 쪽)
local function row(parent: Instance, origin: Vector3, along: Vector3, facing: Vector3, length: number, rng: Random)
	local cursor = 0
	while cursor < length - 10 do
		local width = math.min(rng:NextInteger(14, 20), length - cursor)
		local center = origin + along * (cursor + width / 2)
		local height = rng:NextInteger(4, 10) * 4 + 2
		building(parent, CFrame.lookAt(center, center + facing), width, rng:NextInteger(14, 20), height, rng)
		cursor += width + 1
	end
end

-- 가로등: base는 바닥, toward는 등이 뻗는 쪽(차도). 전구는 낮에는 꺼 두고 해 질 녘에 켠다(Outdoor.client).
local function streetLamp(parent: Instance, base: Vector3, toward: Vector3)
	pillar(parent, 0.35, 9, CFrame.new(base + Vector3.new(0, 4.5, 0)), POLE)
	local tip = base + Vector3.new(0, 9, 0) + toward * 1.8
	local mid = base + Vector3.new(0, 9, 0) + toward * 0.9
	part(parent, Vector3.new(0.2, 0.2, 1.8), CFrame.lookAt(mid, tip), POLE)
	local bulb = ball(parent, 0.9, CFrame.new(tip - Vector3.new(0, 0.3, 0)), WHITE)
	bulb:SetAttribute("StreetLamp", true)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 246, 236)
	light.Range = 20
	light.Brightness = 1.2
	light.Enabled = false
	light.Parent = bulb
end

local function tree(parent: Instance, base: Vector3, rng: Random)
	pillar(parent, 2.6, 0.12, CFrame.new(base + Vector3.new(0, 0.06, 0)), Color3.fromRGB(176, 156, 140))
	pillar(parent, 0.8, 4.4, CFrame.new(base + Vector3.new(0, 2.2, 0)), Color3.fromRGB(156, 120, 96))
	local green = Color3.fromRGB(150, 206, 150)
	ball(parent, 4.4, CFrame.new(base + Vector3.new(0, 5.6, 0)), green)
	for i = 1, 3 do
		local angle = i * 2.1 + rng:NextNumber(0, 0.5)
		ball(parent, 2.8, CFrame.new(base + Vector3.new(math.cos(angle) * 1.6, 6.4, math.sin(angle) * 1.6)), Color3.fromRGB(168, 220, 166))
	end
end

-- 신호등: facing 쪽(차도)을 본다
local function trafficLight(parent: Instance, base: Vector3, facing: Vector3)
	pillar(parent, 0.35, 7, CFrame.new(base + Vector3.new(0, 3.5, 0)), POLE)
	local box = CFrame.lookAt(base + Vector3.new(0, 7.8, 0), base + Vector3.new(0, 7.8, 0) + facing)
	part(parent, Vector3.new(0.9, 2.6, 0.8), box, POLE)
	for i, color in { Color3.fromRGB(240, 110, 110), Color3.fromRGB(246, 200, 110), Color3.fromRGB(120, 210, 140) } do
		ball(parent, 0.55, box * CFrame.new(0, 0.8 - (i - 1) * 0.8, -0.4), color, Enum.Material.Neon)
	end
end

-- 주차된 차: at은 차 가운데 바닥(차도 위), 차는 at의 앞뒤(Z)로 길다
local function car(parent: Instance, at: CFrame, color: Color3)
	part(parent, Vector3.new(4, 1.4, 8), at * CFrame.new(0, 1.3, 0), color)
	part(parent, Vector3.new(3.6, 1.3, 4.4), at * CFrame.new(0, 2.6, 0.4), Color3.fromRGB(222, 238, 250))
	for _, x in { -1.9, 1.9 } do
		for _, z in { -2.6, 2.6 } do
			local wheel = Build.part(parent, CYL, Vector3.new(0.6, 1.4, 1.4), at * CFrame.new(x, 0.7, z), Color3.fromRGB(70, 72, 84))
			wheel.CastShadow = false
		end
	end
	for _, x in { -1.3, 1.3 } do
		ball(parent, 0.5, at * CFrame.new(x, 1.5, -4), WHITE, Enum.Material.Neon)
	end
end

local function bench(parent: Instance, at: CFrame)
	part(parent, Vector3.new(4, 0.3, 1.4), at * CFrame.new(0, 1.3, 0), Color3.fromRGB(196, 150, 120), Enum.Material.WoodPlanks)
	part(parent, Vector3.new(4, 1.2, 0.25), at * CFrame.new(0, 2.1, 0.6), Color3.fromRGB(196, 150, 120), Enum.Material.WoodPlanks)
	for _, x in { -1.6, 1.6 } do
		part(parent, Vector3.new(0.25, 1.2, 1.2), at * CFrame.new(x, 0.6, 0), POLE)
	end
end

function City.build(parent: Instance)
	local root = Instance.new("Folder")
	root.Name = "City"
	root.Parent = parent
	local rng = Random.new(20261102) -- 늘 같은 도시

	-- 땅: 차도 한 판 위에 인도·건물 터를 겹치지 않게 깐다
	local roadFront, roadBack = SHOP_FRONT - ROAD_W, SHOP_BACK + ROAD_W -- 앞·뒤 길 바깥쪽
	local roadSide = SHOP_X + ROAD_W -- 옆길 바깥쪽
	local walk = 8 -- 길 건너 인도 폭
	slab(root, -FAR, FAR, -FAR, FAR, ASPHALT, ROAD, Enum.Material.Asphalt)
	slab(root, -SHOP_X, SHOP_X, SHOP_FRONT, SHOP_BACK, GROUND, WALK, Enum.Material.Pavement)
	for _, side in { -1, 1 } do
		local x0, x1 = if side < 0 then -FAR else roadSide, if side < 0 then -roadSide else FAR
		slab(root, x0, x1, SHOP_FRONT, SHOP_BACK, GROUND, WALK, Enum.Material.Pavement)
	end
	slab(root, -FAR, FAR, roadFront - walk, roadFront, GROUND, WALK, Enum.Material.Pavement)
	slab(root, -FAR, FAR, -FAR, roadFront - walk, GROUND, LOT, Enum.Material.Pavement)
	slab(root, -FAR, FAR, roadBack, roadBack + walk, GROUND, WALK, Enum.Material.Pavement)
	slab(root, -FAR, FAR, roadBack + walk, FAR, GROUND, LOT, Enum.Material.Pavement)

	-- 차선과 횡단보도
	local frontZ, backZ, sideX = SHOP_FRONT - ROAD_W / 2, SHOP_BACK + ROAD_W / 2, SHOP_X + ROAD_W / 2
	-- 점선은 교차로와 횡단보도(앞·뒤 길은 x 0, 옆길은 z -14)에서 끊는다
	local function crossing(p: Vector3): boolean
		return math.abs(math.abs(p.X) - sideX) < ROAD_W / 2 + 1 or math.abs(p.X) < 4
	end
	local function sideCrossing(p: Vector3): boolean
		return math.abs(p.Z + 14) < 4
	end
	dashes(root, Vector3.new(-FAR, 0, frontZ), Vector3.new(FAR, 0, frontZ), crossing)
	dashes(root, Vector3.new(-FAR, 0, backZ), Vector3.new(FAR, 0, backZ), crossing)
	for _, side in { -1, 1 } do
		dashes(root, Vector3.new(side * sideX, 0, SHOP_FRONT), Vector3.new(side * sideX, 0, SHOP_BACK), sideCrossing)
		crosswalk(root, Vector3.new(side * sideX, 0, -14), Vector3.new(1, 0, 0))
	end
	crosswalk(root, Vector3.new(0, 0, frontZ), Vector3.new(0, 0, 1))
	crosswalk(root, Vector3.new(0, 0, backZ), Vector3.new(0, 0, 1))

	-- 길 건너 건물: 앞(가게 정면 건너편), 뒤, 양옆
	local front = roadFront - walk
	local back = roadBack + walk
	row(root, Vector3.new(-FAR + 2, 0, front), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), FAR * 2 - 4, rng)
	row(root, Vector3.new(-FAR + 2, 0, back), Vector3.new(1, 0, 0), Vector3.new(0, 0, -1), FAR * 2 - 4, rng)
	for _, side in { -1, 1 } do
		local x = side * (roadSide + walk)
		row(root, Vector3.new(x, 0, SHOP_FRONT + 1), Vector3.new(0, 0, 1), Vector3.new(-side, 0, 0), SHOP_BACK - SHOP_FRONT - 2, rng)
	end

	-- 가게 블록 인도: 가로등·가로수·벤치(손님이 나타나는 문 앞 길목 z -20~-8은 비운다)
	local edge = 1.5 -- 인도 끝에서 안쪽으로
	for _, x in { -36, -12, 12, 36 } do
		streetLamp(root, Vector3.new(x, GROUND, SHOP_FRONT + edge), Vector3.new(0, 0, -1))
	end
	for _, x in { -24, 24 } do
		tree(root, Vector3.new(x, GROUND, SHOP_FRONT + 4), rng)
		bench(root, CFrame.lookAt(Vector3.new(x * 0.5, GROUND, SHOP_FRONT + 7), Vector3.new(x * 0.5, GROUND, SHOP_FRONT)))
	end
	for _, side in { -1, 1 } do
		for _, z in { -34, 2, 24 } do
			streetLamp(root, Vector3.new(side * (SHOP_X - edge), GROUND, z), Vector3.new(side, 0, 0))
		end
		for _, z in { -30, 8, 20 } do
			tree(root, Vector3.new(side * (SHOP_X - 5), GROUND, z), rng)
		end
		trafficLight(root, Vector3.new(side * (SHOP_X - 0.8), GROUND, SHOP_FRONT + 0.8), Vector3.new(0, 0, -1))
		trafficLight(root, Vector3.new(side * (SHOP_X - 0.8), GROUND, SHOP_BACK - 0.8), Vector3.new(0, 0, 1))
	end
	for _, x in { -30, 0, 30 } do
		streetLamp(root, Vector3.new(x, GROUND, SHOP_BACK - edge), Vector3.new(0, 0, 1))
	end
	-- 길 건너 인도 가로수
	for x = -96, 96, 24 do
		tree(root, Vector3.new(x, GROUND, roadFront - 3), rng)
		tree(root, Vector3.new(x + 12, GROUND, roadBack + 3), rng)
	end

	-- 길가에 세운 차
	local turn = CFrame.Angles(0, math.rad(90), 0)
	car(root, CFrame.new(-30, ASPHALT, roadFront + 3) * turn, Color3.fromRGB(246, 176, 196))
	car(root, CFrame.new(34, ASPHALT, roadFront + 3) * turn, Color3.fromRGB(150, 196, 240))
	car(root, CFrame.new(-74, ASPHALT, SHOP_FRONT - 3) * turn, Color3.fromRGB(160, 214, 180))
	car(root, CFrame.new(roadSide - 3, ASPHALT, 10), Color3.fromRGB(200, 180, 240))
	car(root, CFrame.new(12, ASPHALT, roadBack - 3) * turn, Color3.fromRGB(246, 196, 170))
end

return City
