--!strict
-- 디저트·쟁반·소화기 모델. 서버(주방의 실제 물건)와 클라이언트(손님 말풍선·아이스크림 창 미리보기)가 같이 쓴다.
-- 원점 기준으로 만들고, 투명한 Root 크기가 놓일 때의 부피다(아랫면 = -Root.Size.Y/2). 파트는 모두 Anchored.
-- 상태: 재료 raw / 요리 prepped(조합함) → cooked(익음) → sauced(토핑) / burnt(탐)
-- 아이스크림은 spec(그릇·맛·토핑)으로 모양을 정하고, melt(0 그대로, 1 흘러내림, 2 다 녹음)로 녹는 모습을 보인다.
local Build = require(script.Parent.Build)
local Config = require(script.Parent.Config)

local FoodModels = {}

type Painter = (model: Model, state: string) -> ()

local BLOCK = Enum.PartType.Block
local CYL = Enum.PartType.Cylinder

local BURNT = Color3.fromRGB(70, 48, 40)
local WHITE = Color3.fromRGB(255, 252, 250)
local CREAM = Color3.fromRGB(255, 246, 236)
local LEAF = Color3.fromRGB(110, 186, 96)
local BERRY = Color3.fromRGB(240, 70, 92)
local GOLD = Color3.fromRGB(238, 190, 112)
local GLASS = Color3.fromRGB(236, 246, 255)

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function spin(x: number, y: number, z: number, yaw: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0)
end

local function color(state: string, c: Color3): Color3
	return if state == "burnt" then BURNT else c
end

local function strawberry(model: Model, cframe: CFrame, size: number)
	Build.ball(model, size, cframe, BERRY)
	Build.part(model, BLOCK, Vector3.new(size * 0.55, 0.05, size * 0.55), cframe * spin(0, size * 0.46, 0, 45), LEAF)
	for _, p in { { 0.2, 0.1 }, { -0.18, 0.05 }, { 0.02, -0.22 } } do
		Build.ball(model, size * 0.12, cframe * at(p[1] * size, size * 0.1, p[2] * size - size * 0.36), Color3.fromRGB(255, 236, 160))
	end
end

local function cream(model: Model, cframe: CFrame, size: number)
	Build.ball(model, size, cframe, WHITE)
	Build.ball(model, size * 0.6, cframe * at(0, size * 0.42, 0), WHITE)
end

local function sprinkles(model: Model, y: number, radius: number)
	local colors = { Color3.fromRGB(246, 120, 160), Color3.fromRGB(120, 196, 240), Color3.fromRGB(252, 214, 96), Color3.fromRGB(150, 220, 150) }
	for i = 1, 8 do
		local angle = i * 2.3
		Build.part(model, BLOCK, Vector3.new(0.16, 0.05, 0.05), spin(math.cos(angle) * radius, y, math.sin(angle) * radius, i * 40), colors[i % #colors + 1])
	end
end

-- ── 재료 ──

local INGREDIENTS: { [string]: { size: Vector3, paint: Painter } } = {
	tea = {
		-- 바구니에 수북한 초록 찻잎(멀리서도 '잎'으로 보이게 크고 진하게)
		size = Vector3.new(1.2, 0.9, 1.2),
		paint = function(model)
			Build.disc(model, 1.15, 0.4, at(0, -0.25, 0), Color3.fromRGB(222, 184, 128))
			Build.disc(model, 1.2, 0.08, at(0, -0.06, 0), Color3.fromRGB(196, 152, 98))
			local greens = { Color3.fromRGB(96, 176, 84), Color3.fromRGB(124, 200, 100), Color3.fromRGB(80, 150, 72) }
			for i = 1, 9 do
				local angle = i * 2.1
				local r = if i > 6 then 0.12 else 0.32
				local y = if i > 6 then 0.2 else 0.04
				Build.part(model, BLOCK, Vector3.new(0.5, 0.06, 0.24), CFrame.new(math.cos(angle) * r, y, math.sin(angle) * r) * CFrame.Angles(math.rad(18), angle, math.rad(i * 9)), greens[i % #greens + 1])
			end
			-- 위로 솟은 잎 두 장
			Build.part(model, BLOCK, Vector3.new(0.18, 0.55, 0.06), CFrame.new(-0.12, 0.32, 0) * CFrame.Angles(0, 0, math.rad(25)), LEAF)
			Build.part(model, BLOCK, Vector3.new(0.18, 0.5, 0.06), CFrame.new(0.14, 0.3, 0.05) * CFrame.Angles(0, math.rad(40), math.rad(-20)), Color3.fromRGB(96, 176, 84))
		end,
	},
	milk = {
		size = Vector3.new(0.7, 1.3, 0.7),
		paint = function(model)
			Build.disc(model, 0.6, 0.85, at(0, -0.22, 0), WHITE)
			Build.disc(model, 0.62, 0.22, at(0, -0.2, 0), Color3.fromRGB(150, 200, 246))
			Build.disc(model, 0.36, 0.3, at(0, 0.35, 0), WHITE)
			Build.disc(model, 0.4, 0.14, at(0, 0.56, 0), Color3.fromRGB(246, 150, 180))
		end,
	},
	pearl = {
		size = Vector3.new(1.1, 0.6, 1.1),
		paint = function(model)
			Build.disc(model, 1.05, 0.3, at(0, -0.15, 0), WHITE)
			for i = 1, 9 do
				local angle = i * 2.2
				local r = if i == 9 then 0 else 0.28
				Build.ball(model, 0.2, at(math.cos(angle) * r, 0.08, math.sin(angle) * r), Color3.fromRGB(64, 44, 44))
			end
		end,
	},
	batter = {
		size = Vector3.new(1.2, 0.8, 1.2),
		paint = function(model)
			Build.disc(model, 1.15, 0.55, at(0, -0.12, 0), Color3.fromRGB(196, 228, 248))
			Build.disc(model, 1.0, 0.06, at(0, 0.14, 0), Color3.fromRGB(252, 236, 190))
			Build.part(model, CYL, Vector3.new(0.9, 0.08, 0.08), CFrame.new(0.3, 0.35, 0) * CFrame.Angles(0, 0, math.rad(40)), Color3.fromRGB(200, 204, 210))
			Build.ball(model, 0.26, at(0.62, 0.62, 0), Color3.fromRGB(220, 224, 230))
		end,
	},
	strawberry = {
		size = Vector3.new(1.2, 0.55, 1.0),
		paint = function(model)
			strawberry(model, at(-0.32, 0, 0), 0.48)
			strawberry(model, at(0.3, -0.02, 0.12), 0.44)
			strawberry(model, at(0, -0.02, -0.25), 0.42)
		end,
	},
}

-- ── 음료·디저트 ──

-- 음료: 장난감처럼 통통한 불투명 파스텔 컵(투명 유리 컵은 너무 사실적이라 귀엽지 않았다).
-- 컵 몸통은 음료 색을 연하게, 가운데 띠(sleeve)에 웃는 얼굴과 볼터치, 하얀 둥근 뚜껑, 굵은 줄무늬 빨대.
-- 버블티는 컵 아래를 펄이 빙 두른다. 조합만 하고 끓이기 전(prepped)은 뚜껑 없이 우유 위에 찻잎이 떠 있다.
-- 얼굴은 +Z 쪽(카메라·말풍선 그림이 보는 쪽)에 그린다.
local INK = Color3.fromRGB(70, 50, 52)
local BLUSH = Color3.fromRGB(250, 160, 175)
local PEARL = Color3.fromRGB(70, 48, 46)

local function cupDrink(model: Model, state: string, liquid: Color3, pearls: boolean, sleeve: Color3, straw: Color3)
	local drink = color(state, liquid)
	local body = if state == "burnt" then BURNT else drink:Lerp(WHITE, 0.45)
	-- 아래가 살짝 좁은 통통한 컵
	Build.disc(model, 0.8, 0.5, at(0, -0.7, 0), body)
	Build.disc(model, 0.88, 0.5, at(0, -0.2, 0), body)
	Build.disc(model, 0.96, 0.36, at(0, 0.23, 0), if state == "prepped" then WHITE else drink)
	if state == "prepped" then
		-- 아직 끓이기 전: 우유 위에 찻잎
		Build.disc(model, 0.86, 0.04, at(0, 0.42, 0), Color3.fromRGB(252, 248, 240))
		for i = 1, 4 do
			Build.part(model, BLOCK, Vector3.new(0.22, 0.04, 0.12), spin(math.cos(i) * 0.2, 0.45, math.sin(i) * 0.2, i * 50), LEAF)
		end
	else
		-- 띠와 얼굴
		Build.disc(model, 0.92, 0.38, at(0, -0.22, 0), if state == "burnt" then BURNT else sleeve)
		if state ~= "burnt" then
			for _, x in { -0.13, 0.13 } do
				Build.ball(model, 0.08, at(x, -0.16, 0.44), INK)
				Build.ball(model, 0.1, at(x * 1.9, -0.26, 0.42), BLUSH)
			end
			Build.part(model, BLOCK, Vector3.new(0.1, 0.03, 0.03), at(0, -0.27, 0.46), INK)
		end
		-- 하얀 둥근 뚜껑
		Build.disc(model, 1.0, 0.08, at(0, 0.44, 0), WHITE)
		Build.ball(model, 0.82, at(0, 0.42, 0), WHITE)
		-- 굵은 줄무늬 빨대
		local tilt = CFrame.new(0.14, 0.75, 0) * CFrame.Angles(0, 0, math.rad(-12))
		Build.part(model, CYL, Vector3.new(0.8, 0.17, 0.17), tilt * Build.UP, straw)
		for _, y in { -0.05, 0.2 } do
			Build.part(model, CYL, Vector3.new(0.06, 0.18, 0.18), tilt * CFrame.new(0, y, 0) * Build.UP, WHITE)
		end
	end
	if pearls then
		for i = 1, 8 do
			local angle = i * math.pi / 4
			Build.ball(model, 0.2, at(math.cos(angle) * 0.4, -0.82, math.sin(angle) * 0.4), PEARL)
		end
	end
end

local function waffleSquare(model: Model, y: number, state: string)
	if state == "prepped" then
		Build.disc(model, 1.6, 0.12, at(0, y, 0), Color3.fromRGB(252, 236, 190))
		return
	end
	local base = color(state, GOLD)
	Build.part(model, BLOCK, Vector3.new(1.7, 0.24, 1.7), at(0, y, 0), base)
	if state ~= "burnt" then
		for i = -1, 1 do
			Build.part(model, BLOCK, Vector3.new(1.7, 0.03, 0.08), at(0, y + 0.13, i * 0.45), Build.shade(GOLD, 0.2))
			Build.part(model, BLOCK, Vector3.new(0.08, 0.03, 1.7), at(i * 0.45, y + 0.13, 0), Build.shade(GOLD, 0.2))
		end
	end
end

local DISHES: { [string]: { size: Vector3, paint: Painter } } = {
	milk_tea = {
		size = Vector3.new(1.0, 1.9, 1.0),
		paint = function(model, state)
			cupDrink(model, state, Color3.fromRGB(214, 172, 132), false, Color3.fromRGB(250, 196, 212), Color3.fromRGB(246, 150, 180))
		end,
	},
	bubble_tea = {
		size = Vector3.new(1.0, 1.9, 1.0),
		paint = function(model, state)
			cupDrink(model, state, Color3.fromRGB(226, 186, 150), true, Color3.fromRGB(196, 228, 248), Color3.fromRGB(130, 196, 240))
		end,
	},
	waffle = {
		size = Vector3.new(1.8, 0.5, 1.8),
		paint = function(model, state)
			waffleSquare(model, -0.1, state)
			if state == "cooked" then
				Build.part(model, BLOCK, Vector3.new(0.35, 0.12, 0.35), at(0, 0.08, 0), Color3.fromRGB(255, 232, 150))
			end
		end,
	},
	strawberry_waffle = {
		size = Vector3.new(1.8, 0.9, 1.8),
		paint = function(model, state)
			waffleSquare(model, -0.3, state)
			if state == "burnt" then
				return
			end
			for _, p in { { -0.45, -0.3 }, { 0.4, -0.35 }, { 0.05, 0.4 } } do
				strawberry(model, at(p[1], -0.02, p[2]), 0.4)
			end
			if state == "sauced" then
				cream(model, at(0, 0.05, -0.05), 0.5)
				Build.part(model, BLOCK, Vector3.new(1.3, 0.04, 0.1), spin(0, -0.15, 0.2, 30), Color3.fromRGB(246, 120, 160), Enum.Material.SmoothPlastic, 0.1)
			end
		end,
	},
	strawberry_cake = {
		size = Vector3.new(1.8, 1.3, 1.8),
		paint = function(model, state)
			if state == "prepped" then
				Build.disc(model, 1.7, 0.5, at(0, -0.4, 0), Color3.fromRGB(206, 212, 220), Enum.Material.Metal)
				Build.disc(model, 1.5, 0.06, at(0, -0.14, 0), Color3.fromRGB(252, 236, 190))
				strawberry(model, at(0.3, 0, 0.2), 0.36)
				return
			end
			Build.disc(model, 1.6, 0.8, at(0, -0.25, 0), color(state, Color3.fromRGB(244, 214, 160)))
			Build.disc(model, 1.62, 0.12, at(0, -0.25, 0), color(state, CREAM))
			if state == "sauced" then
				Build.disc(model, 1.64, 0.18, at(0, 0.2, 0), WHITE)
				for i = 1, 6 do
					local angle = i * math.pi / 3
					strawberry(model, at(math.cos(angle) * 0.55, 0.42, math.sin(angle) * 0.55), 0.3)
				end
				cream(model, at(0, 0.42, 0), 0.4)
			end
		end,
	},
}

-- ── 아이스크림 ──

local CONE_LIGHT = Color3.fromRGB(232, 184, 118)
local CONE_DARK = Color3.fromRGB(212, 160, 96)

local function iceBaseHeight(base: string): number
	return if base == "cone" then 1.2 else 0.6
end

local function iceBase(model: Model, base: string, bottom: number)
	if base == "cone" then
		-- 끝이 아래로 가는 콘: 지름이 커지는 원판을 쌓는다
		local steps = 6
		local height = iceBaseHeight(base)
		for i = 1, steps do
			local t = i / steps
			Build.disc(model, 0.18 + 0.72 * t, height / steps + 0.02, at(0, bottom + (i - 0.5) * height / steps, 0), if i % 2 == 0 then CONE_DARK else CONE_LIGHT)
		end
	else
		Build.disc(model, 1.0, 0.6, at(0, bottom + 0.3, 0), Color3.fromRGB(190, 224, 246))
		Build.disc(model, 1.02, 0.12, at(0, bottom + 0.35, 0), Color3.fromRGB(250, 176, 198))
	end
end

local function flavorColor(id: string): Color3
	local option = Config.findIceOption(Config.IceCream.flavors, id)
	return if option then option.color else WHITE
end

local function iceHeight(spec: Config.IceSpec): number
	return iceBaseHeight(spec.base) + 0.5 + 0.38 * #spec.flavors + 0.3
end

local function icecream(spec: Config.IceSpec, melt: number): Model
	local height = iceHeight(spec)
	local model = Build.model("icecream", Vector3.new(1.2, height, 1.2))
	local bottom = -height / 2
	iceBase(model, spec.base, bottom)
	local top = bottom + iceBaseHeight(spec.base)
	if #spec.flavors == 0 then
		return model -- 아이스크림 창에서 아직 맛을 고르기 전
	end
	if melt >= 2 then
		-- 다 녹음: 납작한 웅덩이와 작은 덩어리만 남는다
		local first = flavorColor(spec.flavors[1])
		Build.disc(model, 0.95, 0.12, at(0, top + 0.06, 0), first)
		Build.ball(model, 0.45, at(0.1, top + 0.18, 0), first)
		Build.disc(model, 1.15, 0.04, at(0.15, bottom + 0.02, 0.1), first)
		return model
	end
	-- 아래부터 한 층씩 쌓은 소프트아이스크림
	local y = top + 0.2
	for i, flavor in spec.flavors do
		local size = 0.92 - (i - 1) * 0.1
		Build.ball(model, size, at(0, y, 0), flavorColor(flavor))
		y += 0.38
	end
	local last = flavorColor(spec.flavors[#spec.flavors])
	Build.ball(model, 0.34, at(0, y - 0.05, 0), last)
	local crown = y - 0.12
	local topping = spec.topping
	if topping == "sprinkles" then
		sprinkles(model, crown, 0.22)
	elseif topping == "berry" then
		strawberry(model, at(0.05, crown + 0.12, 0), 0.36)
	elseif topping == "chip" then
		for i = 1, 6 do
			local angle = i * 1.1
			Build.part(model, BLOCK, Vector3.new(0.12, 0.08, 0.12), spin(math.cos(angle) * 0.25, crown - 0.05, math.sin(angle) * 0.25, i * 30), Color3.fromRGB(96, 60, 44))
		end
	elseif topping == "cherry" then
		Build.ball(model, 0.3, at(0, crown + 0.2, 0), Color3.fromRGB(214, 30, 52))
		Build.part(model, BLOCK, Vector3.new(0.04, 0.3, 0.04), CFrame.new(0.05, crown + 0.42, 0) * CFrame.Angles(0, 0, math.rad(-20)), Color3.fromRGB(96, 140, 70))
	end
	if melt >= 1 then
		-- 흘러내림: 첫 층 맛이 그릇 가장자리로 흐른다
		local first = flavorColor(spec.flavors[1])
		for i = 1, 4 do
			local angle = i * math.pi / 2 + 0.4
			Build.ball(model, 0.2, at(math.cos(angle) * 0.42, top - 0.12, math.sin(angle) * 0.42), first)
		end
	end
	return model
end

local function tray(model: Model)
	Build.disc(model, 2.6, 0.12, at(0, -0.04, 0), Color3.fromRGB(196, 228, 248))
	Build.disc(model, 2.66, 0.06, at(0, -0.07, 0), WHITE)
	Build.disc(model, 1.7, 0.13, at(0, -0.03, 0), Color3.fromRGB(255, 236, 242))
end

-- 홀 테이블에서 치운 빈 그릇: 크림 묻은 접시 두 장과 빈 컵
local function dishes(model: Model)
	Build.disc(model, 1.3, 0.08, at(0, -0.3, 0), WHITE)
	Build.disc(model, 1.2, 0.08, at(0.05, -0.2, 0.03), Color3.fromRGB(255, 236, 242))
	Build.ball(model, 0.28, at(0.25, -0.1, 0.1), WHITE)
	Build.ball(model, 0.18, at(-0.3, -0.12, -0.2), Color3.fromRGB(250, 176, 198))
	local cup = Build.disc(model, 0.45, 0.55, at(-0.35, 0.1, 0.3), GLASS)
	cup.Transparency = 0.35
end

local function extinguisher(model: Model)
	Build.disc(model, 0.8, 1.5, at(0, -0.2, 0), Color3.fromRGB(232, 70, 76))
	Build.part(model, BLOCK, Vector3.new(0.36, 0.3, 0.36), at(0, 0.7, 0), Color3.fromRGB(60, 56, 60))
	Build.part(model, BLOCK, Vector3.new(0.7, 0.08, 0.18), at(0.1, 0.9, 0), Color3.fromRGB(60, 56, 60))
	Build.part(model, CYL, Vector3.new(0.5, 0.12, 0.12), CFrame.new(-0.3, 0.6, 0) * CFrame.Angles(0, 0, math.rad(-40)), Color3.fromRGB(60, 56, 60))
end

function FoodModels.isIngredient(kind: string): boolean
	return INGREDIENTS[kind] ~= nil
end

-- kind: 재료 키, 요리 키, "icecream"(spec 필요), "plate"(쟁반), "dishes"(치운 빈 그릇), "extinguisher"
function FoodModels.build(kind: string, state: string, melt: number?, spec: Config.IceSpec?): Model
	if kind == "icecream" and spec then
		return icecream(spec, melt or 0)
	end
	local ingredient = INGREDIENTS[kind]
	if ingredient then
		local model = Build.model(kind, ingredient.size)
		ingredient.paint(model, state)
		return model
	end
	local dish = DISHES[kind]
	if dish then
		local model = Build.model(kind, dish.size)
		dish.paint(model, state)
		if state == "burnt" then
			local smoke = Instance.new("Smoke")
			smoke.Color = Color3.fromRGB(90, 90, 90)
			smoke.Opacity = 0.12
			smoke.RiseVelocity = 2
			smoke.Size = 0.8
			smoke.Parent = model.PrimaryPart
		end
		return model
	end
	if kind == "plate" then
		local model = Build.model(kind, Vector3.new(2.6, 0.2, 2.6))
		tray(model)
		return model
	elseif kind == "dishes" then
		local model = Build.model(kind, Vector3.new(1.4, 0.7, 1.4))
		dishes(model)
		return model
	end
	local model = Build.model(kind, Vector3.new(0.9, 2, 0.9))
	extinguisher(model)
	return model
end

return FoodModels
