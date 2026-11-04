--!strict
-- 로비 광장: 도시(City) 한가운데 블록(x -44~44, z -44~32, 게임에서는 가게가 서는 곳)을 광장으로 쓴다.
--   뒤쪽(+Z) 시작 자리 → 가운데 아이스크림 동상 분수 → 가게 문 모양 발판 넷 → 앞쪽(-Z) 큰 간판
-- 도시 파트는 충돌이 없어서 광장 바닥을 따로 깔고, 광장 밖(차도)으로는 못 나가게 투명 벽을 두른다.
-- 조명은 가게와 같은 살짝 따뜻한 중립 흰빛(Store.mood와 같은 값).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Build = require(ReplicatedStorage.Shared.Build)
local Config = require(ReplicatedStorage.Shared.Config)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)
local City = require(script.Parent.City)

-- 발판 하나: 가운데(바닥), 상태 글(머리 위 팻말), 빛나는 테두리(상태에 따라 색이 바뀐다)
export type PadSpec = { index: number, center: Vector3, label: TextLabel, ring: BasePart }
export type Built = { pads: { PadSpec } }

local BLOCK = Enum.PartType.Block
local WHITE = Color3.fromRGB(255, 255, 255)
local PINK = Color3.fromRGB(246, 196, 214)
local PINK_DEEP = Color3.fromRGB(236, 132, 160)
local SKY = Color3.fromRGB(196, 226, 246)
local MINT = Color3.fromRGB(196, 236, 214)
local CORAL = Color3.fromRGB(236, 132, 100)
local FLOOR = Color3.fromRGB(248, 238, 240)

local HALF_X, FRONT, BACK = 44, -44, 32 -- 광장 테두리(City의 가게 블록과 같다)
local PAD_Z = -22
local PAD_X = { -27, -9, 9, 27 }
local PAD_SIZE = 10
local PAD_COLORS = { PINK, SKY, MINT, Color3.fromRGB(226, 214, 246) }

local Plaza = {}

Plaza.PAD_RADIUS = PAD_SIZE / 2

local function solid(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Build.part(parent, BLOCK, size, cframe, color, material)
	part.CanCollide = true
	part.CanQuery = true
	return part
end

local function wall(parent: Instance, size: Vector3, position: Vector3)
	local part = solid(parent, size, CFrame.new(position), WHITE)
	part.Transparency = 1
	part.Name = "Barrier"
end

-- 판(part)의 앞면(-Z)에 글을 붙인다
local function sign(part: BasePart, lines: { { text: string, size: number, color: Color3 } })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	local layout = Instance.new("UIListLayout")
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.LayoutOrder = i
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(0.94, 0, line.size, 0)
		label.Text = line.text
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = line.color
		label.Parent = gui
	end
	gui.Parent = part
end

-- 가게와 같은 조명(살짝 따뜻한 중립 흰빛)
local function mood()
	Lighting.Ambient = Color3.fromRGB(126, 122, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(146, 142, 140)
	Lighting.Brightness = 1.5
	Lighting.ClockTime = 13.5
	Lighting.GeographicLatitude = 30
	Lighting.ExposureCompensation = -0.25
	Lighting.EnvironmentSpecularScale = 0.2
	Lighting.EnvironmentDiffuseScale = 0.25
	local tint = Instance.new("ColorCorrectionEffect")
	tint.TintColor = Color3.fromRGB(255, 252, 248)
	tint.Saturation = 0.14
	tint.Contrast = 0.1
	tint.Parent = Lighting
end

-- 발판 하나: 빛나는 테두리 위 둥근 판, 뒤에 가게 문 모양 아치("가게 1"), 위에 상태 팻말
local function pad(parent: Instance, index: number, x: number): PadSpec
	local center = Vector3.new(x, 0, PAD_Z)
	local color = PAD_COLORS[(index - 1) % #PAD_COLORS + 1]
	local ring = Build.disc(parent, PAD_SIZE + 0.8, 0.2, CFrame.new(x, 0.1, PAD_Z), WHITE, Enum.Material.Neon)
	local top = Build.disc(parent, PAD_SIZE, 0.4, CFrame.new(x, 0.2, PAD_Z), color)
	top.CanCollide = true
	-- 아치: 기둥 둘과 줄무늬 차양, 간판
	local back = PAD_Z - PAD_SIZE / 2 - 0.8
	for _, side in { -1, 1 } do
		solid(parent, Vector3.new(1, 8, 1), CFrame.new(x + side * 4.6, 4, back), WHITE)
	end
	local stripes = 6
	for i = 0, stripes - 1 do
		local sx = x - 5 + (i + 0.5) * (10 / stripes)
		Build.part(parent, BLOCK, Vector3.new(10 / stripes, 0.2, 2), CFrame.new(sx, 8.1, back + 0.9) * CFrame.Angles(math.rad(20), 0, 0), if i % 2 == 0 then PINK_DEEP else WHITE)
	end
	local board = solid(parent, Vector3.new(10.4, 1.8, 0.6), CFrame.lookAt(Vector3.new(x, 9.4, back), Vector3.new(x, 9.4, back + 1)), WHITE)
	sign(board, { { text = `가게 {index}`, size = 0.9, color = CORAL } })

	-- 상태 팻말(머리 위)
	local anchor = Build.part(parent, BLOCK, Vector3.new(0.2, 0.2, 0.2), CFrame.new(x, 6, PAD_Z), WHITE)
	anchor.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 74)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(255, 251, 244)
	label.BackgroundTransparency = 0.05
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextColor3 = Color3.fromRGB(86, 66, 56)
	label.TextWrapped = true
	label.Text = ""
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = anchor
	return { index = index, center = center, label = label, ring = ring }
end

function Plaza.build(): Built
	local root = Instance.new("Folder")
	root.Name = "Lobby"
	City.build(root)
	mood()

	-- 광장 바닥과 투명 벽
	solid(root, Vector3.new(HALF_X * 2, 1, BACK - FRONT), CFrame.new(0, -0.5, (FRONT + BACK) / 2), FLOOR, Enum.Material.SmoothPlastic)
	Build.disc(root, 34, 0.06, CFrame.new(0, 0.03, 2), SKY)
	Build.disc(root, 30, 0.08, CFrame.new(0, 0.05, 2), WHITE)
	wall(root, Vector3.new(1, 30, BACK - FRONT), Vector3.new(-HALF_X - 0.5, 15, (FRONT + BACK) / 2))
	wall(root, Vector3.new(1, 30, BACK - FRONT), Vector3.new(HALF_X + 0.5, 15, (FRONT + BACK) / 2))
	wall(root, Vector3.new(HALF_X * 2, 30, 1), Vector3.new(0, 15, FRONT - 0.5))
	wall(root, Vector3.new(HALF_X * 2, 30, 1), Vector3.new(0, 15, BACK + 0.5))

	-- 시작 자리(뒤쪽)
	local spawn = Instance.new("SpawnLocation")
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, -0.4, 22)
	spawn.Color = MINT
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root

	-- 가운데 분수와 큰 아이스크림 동상
	local basin = Build.disc(root, 16, 1.6, CFrame.new(0, 0.8, 2), WHITE)
	basin.CanCollide = true
	Build.disc(root, 14.4, 0.2, CFrame.new(0, 1.62, 2), Color3.fromRGB(170, 214, 244), Enum.Material.SmoothPlastic, 0.2)
	local pedestal = Build.disc(root, 3.4, 3.2, CFrame.new(0, 3.2, 2), PINK)
	pedestal.CanCollide = true
	local statue = FoodModels.build("icecream", "cooked", 0, { base = "cone", flavors = { "strawberry", "mint", "vanilla" }, topping = "cherry" })
	statue:ScaleTo(4.5)
	local statueRoot = statue.PrimaryPart :: BasePart
	statue:PivotTo(CFrame.new(0, 4.8 + statueRoot.Size.Y / 2, 2))
	statue.Parent = root

	-- 앞쪽 큰 간판(시작 자리 쪽을 본다)
	local signAt = Vector3.new(0, 12, FRONT + 4)
	solid(root, Vector3.new(34.8, 9.8, 0.4), CFrame.lookAt(signAt - Vector3.new(0, 0, 0.3), signAt + Vector3.new(0, 0, 1)), PINK_DEEP)
	local board = solid(root, Vector3.new(34, 9, 0.4), CFrame.lookAt(signAt, signAt + Vector3.new(0, 0, 1)), WHITE)
	sign(board, {
		{ text = "동물 디저트 카페", size = 0.5, color = CORAL },
		{ text = `발판에 올라서면 한 팀(1~{Config.Lobby.teamSize}명)! 같이 가게를 열어요`, size = 0.24, color = Color3.fromRGB(110, 90, 80) },
	})
	for _, side in { -1, 1 } do
		solid(root, Vector3.new(1, 7.5, 1), CFrame.new(side * 14, 3.75, FRONT + 4), WHITE)
	end

	local pads = {}
	for i, x in PAD_X do
		table.insert(pads, pad(root, i, x))
	end

	root.Parent = workspace
	return { pads = pads }
end

return Plaza
