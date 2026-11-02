--!strict
-- 동물 디저트 카페 하나: 뒤쪽 주방 + 앞쪽 주문 카운터 + 손님 홀. 카메라는 주방 뒤 위에서 카운터 쪽을 내려다본다.
--   z 17.75 낮은 뒷벽 ─ 아이스크림 기계·재료 상자 줄 ─ 넓은 통로(6칸, 여럿이 지나가게) ─ 조합대·토핑대 / 조리대·오븐 섬
--   ─ 통로 ─ 주문 카운터(z -7) ─ 손님 줄(z -10) ─ 홀 테이블
-- 왼쪽 벽에 와플 기계, 오른쪽 벽에 티 냄비. 세 번째 기구와 와플 기계·오븐·토핑대는 그 메뉴가 나오는 날 열린다.
-- 카메라가 뒷벽 너머 위에서 보므로 뒷벽은 낮게 둔다(높으면 재료 상자를 가린다).
-- 기구 사이에 캐릭터가 반쯤 들어가 끼는 틈이 없게 벽 쪽 줄은 빈틈없이 붙이고, 뒷줄 뒤쪽은 투명 벽으로 채운다.
-- 카운터 양 끝은 홀로 나가는 통로다(홀 테이블 치우기, Config.DineIn).
-- 색은 연분홍·연하늘 파스텔. 분홍·흰 체크 바닥, 줄무늬 벽, 풍선·가랜드·큰 아이스크림 장식.
-- 가게는 도시 한가운데 블록에 있다(City). 가게 안 조명은 늘 켜 두고, 전체 조명(Lighting)은 하루 내내 바꾸지 않는다.
-- 바깥의 시간 흐름(아침 → 노을 → 밤)은 Outdoor.client가 도시 파트 색으로만 보여 준다(지붕이 없어 해·하늘빛을 바꾸면 가게 안도 바뀐다).
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(ReplicatedStorage.Shared.Build)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)
local Props = require(script.Parent.Props)
local City = require(script.Parent.City)

export type StationSpec = {
	kind: string, -- icemachine | crate | board | grill | pot | oven | sauce | counter | plates | trash | extinguisher | seat
	name: string,
	built: Props.Built,
	ingredient: string?, -- crate
	seat: number?, -- seat: 손님 자리 번호
	lockId: string?, -- 잠금 이름(ing:재료, menu:grill, up:grill3 …). 없으면 처음부터 열림
}

export type Seat = { index: number, stand: CFrame } -- 손님이 서는 자리(주방 쪽을 본다)

-- 홀 테이블: 손님이 앉는 자리(발밑, 테이블을 본다)와 디저트를 놓는 곳
export type TableSpec = { index: number, model: Model, top: BasePart, center: Vector3, seats: { CFrame }, food: { CFrame } }

-- 손님 출입문 한 짝: 영업할 때 바깥쪽으로 열고, 마감하면 닫는다
export type Door = { panel: BasePart, closed: CFrame, open: CFrame }

export type Layout = {
	root: Folder,
	customers: Folder,
	items: Folder,
	stations: { StationSpec },
	seats: { Seat },
	tables: { TableSpec },
	doors: { Door },
	lane: { entry: Vector3, exit: Vector3, z: number }, -- 손님이 들어와 걷는 길
	spawn: CFrame, -- 플레이어 캐릭터가 서는 곳(HumanoidRootPart 기준)
}

local BLOCK = Enum.PartType.Block
local TOP = Props.TOP
local PINK, PINK_DEEP, SKY, SKY_DEEP, WHITE, BUTTER, MINT = Props.PINK, Props.PINK_DEEP, Props.SKY, Props.SKY_DEEP, Props.WHITE, Props.BUTTER, Props.MINT

local INK_DARK = Color3.fromRGB(86, 66, 56)
local BABY = Color3.fromRGB(248, 214, 226) -- 아기 분홍(하얀 땡땡이 바탕)

local SOUTH = CFrame.identity -- 앞이 -Z(카운터 쪽)
local NORTH = CFrame.Angles(0, math.rad(180), 0) -- 앞이 +Z(뒷벽 쪽)
local EAST = CFrame.Angles(0, math.rad(-90), 0) -- 앞이 +X
local WEST = CFrame.Angles(0, math.rad(90), 0) -- 앞이 -X

local SEAT_X = { -11, -5.5, 0, 5.5, 11 }
local DAY_CLOCK = 13.5 -- 해가 높이 떠서 그림자가 짧은 오후
local COUNTER_Z = -7
local BACK_Z = 15.5 -- 뒷줄(아이스크림 기계 둘·재료 상자·쟁반) 가운데. 섬(z 7.5까지)과의 통로가 6칸
local STAND_Z = -10.3

local Store = {}

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Build.part(parent, BLOCK, size, cframe, color, material)
	part.Name = name
	part.CanCollide = true
	part.CanQuery = true
	return part
end

local function barrier(parent: Instance, size: Vector3, position: Vector3)
	local part = block(parent, "Barrier", size, CFrame.new(position), WHITE)
	part.Transparency = 1
end

-- 아래는 연하늘, 위는 아기 분홍(하얀 땡땡이는 decorate가 안쪽 면에 찍는다. 땡땡이는 벽에만)
local function wall(parent: Instance, size: Vector3, center: Vector3)
	local low = 3
	block(parent, "WallLow", Vector3.new(size.X, low, size.Z), CFrame.new(center.X, low / 2, center.Z), SKY, Enum.Material.Plaster)
	block(parent, "WallHigh", Vector3.new(size.X, size.Y - low, size.Z), CFrame.new(center.X, low + (size.Y - low) / 2, center.Z), BABY)
	block(parent, "WallTrim", Vector3.new(size.X + 0.1, 0.3, size.Z + 0.1), CFrame.new(center.X, low, center.Z), WHITE)
end

-- 가게 안 조명 세기. 너무 밝으면 흰 벽·바닥이 하얗게 날아가서(플레이 테스트) 아주 은은하게 둔다.
-- 켜진 느낌은 벽 위 조명 띠와 벽등 전구(네온)가 낸다.
-- 플레이 테스트: 벽등 0.35·채움 0.3에 밝은 주변광·대기 안개를 더했더니 화면이 하얗게 날아가 하나도 안 보였다.
local INDOOR_LIGHT = Color3.fromRGB(255, 250, 244) -- 아주 살짝 따뜻한 흰 빛
local WALL_LAMP_BRIGHTNESS = 0.2
local FILL_BRIGHTNESS = 0.1

-- 벽등(늘 켜 둔다)
local function lamp(parent: Instance, position: Vector3, color: Color3)
	local bulb = Build.ball(parent, 0.9, CFrame.new(position), color, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = INDOOR_LIGHT
	light.Range = 14
	light.Brightness = WALL_LAMP_BRIGHTNESS
	light.Shadows = false
	light.Parent = bulb
end

-- 가게 안 조명: 벽 위쪽에 두른 흰 조명 띠(켜진 게 보이게)와, 천장 높이의 보이지 않는 채움 조명.
-- 천장은 없다(카메라가 위에서 본다).
local function indoorLights(parent: Instance)
	local function strip(size: Vector3, position: Vector3)
		local glow = Build.part(parent, BLOCK, size, CFrame.new(position), WHITE, Enum.Material.Neon)
		glow.CastShadow = false
	end
	for _, side in { -1, 1 } do
		strip(Vector3.new(0.12, 0.18, 23.5), Vector3.new(side * 19.44, 7.82, 6)) -- 주방 옆벽(높이 8)
	end
	strip(Vector3.new(56, 0.18, 0.12), Vector3.new(0, 8.82, -27.94)) -- 홀 앞벽(높이 9)
	local spots = {}
	for _, x in { -12, 0, 12 } do
		for _, z in { 3, 12 } do
			table.insert(spots, Vector3.new(x, 11, z)) -- 주방
		end
	end
	for _, x in { -18, -6, 6, 18 } do
		for _, z in { -12, -22 } do
			table.insert(spots, Vector3.new(x, 11, z)) -- 홀
		end
	end
	for _, spot in spots do
		local holder = Build.part(parent, BLOCK, Vector3.new(0.2, 0.2, 0.2), CFrame.new(spot), WHITE)
		holder.Name = "CeilingLight"
		holder.Transparency = 1
		holder.CastShadow = false
		local light = Instance.new("PointLight")
		light.Color = INDOOR_LIGHT
		light.Range = 18
		light.Brightness = FILL_BRIGHTNESS
		light.Shadows = false
		light.Parent = holder
	end
end

-- 출입문 한 짝: hinge에서 dir(+1이면 +Z, -1이면 -Z) 쪽으로 뻗고, outward(-1 왼쪽 벽, +1 오른쪽 벽) 바깥으로 열린다.
-- 판 하나를 고정하고 테두리·창·손잡이는 판에 용접해서, 판 CFrame만 트윈하면 같이 움직인다.
local function doorLeaf(parent: Instance, hinge: CFrame, dir: number, outward: number): Door
	local offset = CFrame.new(0, 3.5, dir * 2.2)
	local closed = hinge * offset
	local panel = Build.part(parent, BLOCK, Vector3.new(0.3, 7, 4.4), closed, PINK)
	local trims = {
		Build.part(parent, BLOCK, Vector3.new(0.36, 0.3, 4.4), closed * CFrame.new(0, 3.35, 0), WHITE),
		Build.part(parent, BLOCK, Vector3.new(0.36, 0.3, 4.4), closed * CFrame.new(0, -3.35, 0), WHITE),
		Build.part(parent, BLOCK, Vector3.new(0.36, 7, 0.3), closed * CFrame.new(0, 0, dir * 2.05), WHITE),
		Build.part(parent, Enum.PartType.Cylinder, Vector3.new(0.34, 1.6, 1.6), closed * CFrame.new(0, 1.5, 0), Color3.fromRGB(220, 240, 252), Enum.Material.Glass),
		Build.ball(parent, 0.35, closed * CFrame.new(0.25, -0.2, dir * 1.7), Color3.fromRGB(232, 190, 104)),
		Build.ball(parent, 0.35, closed * CFrame.new(-0.25, -0.2, dir * 1.7), Color3.fromRGB(232, 190, 104)),
	}
	trims[4].Transparency = 0.3
	for _, part in trims do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = panel
		weld.Part1 = part
		weld.Parent = part
		part.Anchored = false
	end
	return { panel = panel, closed = closed, open = hinge * CFrame.Angles(0, math.rad(outward * dir * 90), 0) * offset }
end

-- 체크 무늬 바닥(분홍·흰 타일)
local function checker(parent: Instance, center: Vector3, size: Vector2, tile: number, a: Color3, b: Color3)
	local nx = math.floor(size.X / tile + 0.5)
	local nz = math.floor(size.Y / tile + 0.5)
	local wx, wz = size.X / nx, size.Y / nz
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local x = center.X - size.X / 2 + (i + 0.5) * wx
			local z = center.Z - size.Y / 2 + (j + 0.5) * wz
			block(parent, "Tile", Vector3.new(wx, 1, wz), CFrame.new(x, -0.5, z), if (i + j) % 2 == 0 then a else b, Enum.Material.SmoothPlastic)
		end
	end
end

local function balloon(parent: Instance, position: Vector3, color: Color3)
	Build.ball(parent, 1.6, CFrame.new(position), color, Enum.Material.SmoothPlastic)
	Build.part(parent, Enum.PartType.Cylinder, Vector3.new(position.Y - 0.8, 0.05, 0.05), CFrame.new(position.X, (position.Y - 0.8) / 2, position.Z) * Build.UP, WHITE)
end

local function plant(parent: Instance, position: Vector3)
	Build.disc(parent, 1.6, 1.4, CFrame.new(position + Vector3.new(0, 0.7, 0)), WHITE)
	Build.disc(parent, 1.65, 0.3, CFrame.new(position + Vector3.new(0, 1.2, 0)), PINK)
	Build.ball(parent, 2.2, CFrame.new(position + Vector3.new(0, 2.3, 0)), Color3.fromRGB(150, 206, 150))
	Build.ball(parent, 1.6, CFrame.new(position + Vector3.new(0.6, 3.1, 0.3)), Color3.fromRGB(168, 220, 166))
	Build.ball(parent, 0.45, CFrame.new(position + Vector3.new(-0.5, 3.0, -0.6)), PINK_DEEP)
end

local function tableSet(parent: Instance, index: number, position: Vector3, chair: Color3): TableSpec
	local model = Instance.new("Model")
	model.Name = "테이블"
	model:SetAttribute("Kind", "table")
	Build.disc(model, 0.5, 2.6, CFrame.new(position + Vector3.new(0, 1.3, 0)), PINK_DEEP)
	local top = Build.disc(model, 3.6, 0.2, CFrame.new(position + Vector3.new(0, 2.7, 0)), WHITE)
	Build.disc(model, 3.7, 0.08, CFrame.new(position + Vector3.new(0, 2.62, 0)), PINK)
	local seats, food = {}, {}
	for _, x in { -2.6, 2.6 } do
		local seat = position + Vector3.new(x, 0, 0)
		Build.disc(model, 0.4, 1.6, CFrame.new(seat + Vector3.new(0, 0.8, 0)), WHITE)
		Build.disc(model, 1.7, 0.4, CFrame.new(seat + Vector3.new(0, 1.75, 0)), chair)
		table.insert(seats, CFrame.lookAt(seat, position))
		table.insert(food, CFrame.new(position + Vector3.new(x * 0.38, 2.8, 0)))
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = true
		end
	end
	model.Parent = parent
	return { index = index, model = model, top = top, center = position, seats = seats, food = food }
end

-- 가랜드: 분홍·하늘·노랑 삼각 깃발
local function bunting(parent: Instance, from: Vector3, to: Vector3, count: number)
	local colors = { PINK_DEEP, SKY_DEEP, BUTTER, MINT }
	for i = 1, count do
		local t = (i - 0.5) / count
		local p = from:Lerp(to, t) - Vector3.new(0, math.sin(t * math.pi) * 0.8, 0)
		Build.part(parent, BLOCK, Vector3.new(0.9, 0.9, 0.1), CFrame.new(p) * CFrame.Angles(0, 0, math.rad(45)), colors[i % #colors + 1])
	end
end

local function bigCone(parent: Instance, position: Vector3, flavors: { string })
	local cone = FoodModels.build("icecream", "cooked", 0, { base = "cone", flavors = flavors, topping = "sprinkles" })
	cone:ScaleTo(1.8)
	cone:PivotTo(CFrame.new(position + Vector3.new(0, (cone.PrimaryPart :: BasePart).Size.Y / 2, 0)))
	cone.Parent = parent
end

-- 아기자기한 소품들. 카메라가 주방 뒤 위에서 보므로 기구·손님을 가리지 않는 곳(벽, 바닥, 테이블 위, 카운터 가장자리)에만 둔다.
local function decorate(deco: Instance, tables: { TableSpec })
	local CYL = Enum.PartType.Cylinder
	local NEON = Enum.Material.Neon
	local sweets = { PINK_DEEP, SKY_DEEP, BUTTER, MINT, Color3.fromRGB(214, 190, 240) }

	-- 홀 창문: 분홍 커튼 양쪽, 묶는 끈, 위에 흰 레이스
	for _, x in { -16, 0, 16 } do
		for _, side in { -1, 1 } do
			local cx = x + side * 3.9
			Build.part(deco, BLOCK, Vector3.new(1.4, 4.8, 0.25), CFrame.new(cx, 4.9, -27.7), PINK)
			for i = -1, 1 do
				Build.part(deco, BLOCK, Vector3.new(0.12, 4.6, 0.28), CFrame.new(cx + i * 0.4, 4.9, -27.68), Build.shade(PINK, 0.06))
			end
			Build.ball(deco, 0.45, CFrame.new(cx, 4.1, -27.5), BUTTER)
		end
		for i = 0, 9 do
			Build.ball(deco, 0.5, CFrame.new(x - 3.6 + i * 0.8, 6.8, -27.7), WHITE)
		end
	end

	-- 앞벽 액자 두 개(창문 사이): 하늘·노랑 바탕에 아이스크림
	for i, x in { -8, 8 } do
		Build.part(deco, BLOCK, Vector3.new(2.8, 3.2, 0.2), CFrame.new(x, 4.8, -27.95), WHITE)
		Build.part(deco, BLOCK, Vector3.new(2.3, 2.7, 0.22), CFrame.new(x, 4.8, -27.93), if i == 1 then SKY else BUTTER)
		local cone = FoodModels.build("icecream", "cooked", 0, { base = "cone", flavors = if i == 1 then { "strawberry", "mint" } else { "vanilla", "chocolate" }, topping = "cherry" })
		cone:ScaleTo(0.9)
		cone:PivotTo(CFrame.new(x, 4.7, -27.6))
		cone.Parent = deco
	end

	-- 벽 위쪽 안쪽 면에 하얀 땡땡이(아기 분홍 바탕). 창문·커튼·액자·선반·시계·등 자리는 비운다.
	local function near(position: Vector3, x: number, z: number, halfX: number, halfZ: number, minY: number, maxY: number): boolean
		return math.abs(position.X - x) < halfX and math.abs(position.Z - z) < halfZ and position.Y > minY and position.Y < maxY
	end
	local function frontWallSkip(position: Vector3): boolean
		for _, x in { -16, 0, 16 } do
			if math.abs(position.X - x) < 4.9 and position.Y < 7.6 then
				return true
			end
		end
		return math.abs(math.abs(position.X) - 8) < 1.8 and position.Y < 6.7
	end
	local function kitchenWallSkip(position: Vector3): boolean
		return near(position, position.X, 9, 1, 3.8, 6.0, 9) -- 선반
			or near(position, position.X, 2, 1, 1.4, 5.2, 9) -- 시계·하트
			or near(position, position.X, 13, 1, 0.8, 6.4, 9) -- 등
			or near(position, position.X, 4, 1, 0.8, 6.4, 9)
	end
	local frontFace = Vector3.new(0, 6, -27.99)
	Build.polka(deco, CFrame.lookAt(frontFace, frontFace + Vector3.new(0, 0, 1)), 56, 5.6, 1.8, 0.7, WHITE, frontWallSkip)
	for _, side in { -1, 1 } do
		local kitchenFace = Vector3.new(side * 19.49, 5.5, 6)
		Build.polka(deco, CFrame.lookAt(kitchenFace, kitchenFace + Vector3.new(-side, 0, 0)), 23, 4.6, 1.8, 0.7, WHITE, kitchenWallSkip)
		for _, segment in { { z = -23, length = 10 }, { z = -7.25, length = 3.5 } } do
			local hallFace = Vector3.new(side * 27.99, 6, segment.z)
			Build.polka(deco, CFrame.lookAt(hallFace, hallFace + Vector3.new(-side, 0, 0)), segment.length - 0.4, 5.6, 1.8, 0.7, WHITE)
		end
	end

	-- 벽 위 가장자리: 흰 레이스(작은 공을 촘촘히)와 분홍 리본. 벽 안쪽 면(face)의 위쪽 끝을 따라 붙인다.
	local RIBBON = Color3.fromRGB(246, 160, 186)
	local function ribbonBow(at: CFrame, size: number)
		for _, side in { -1, 1 } do
			Build.blob(deco, Vector3.new(0.7, 0.5, 0.2) * size, at * CFrame.new(side * 0.34 * size, 0, 0) * CFrame.Angles(0, 0, math.rad(side * 18)), RIBBON)
			Build.blob(deco, Vector3.new(0.2, 0.6, 0.08) * size, at * CFrame.new(side * 0.14 * size, -0.38 * size, 0) * CFrame.Angles(0, 0, math.rad(side * -14)), RIBBON)
		end
		Build.ball(deco, 0.26 * size, at * CFrame.new(0, 0, -0.04 * size), Build.shade(RIBBON, 0.08))
	end
	-- face: 벽 안쪽 면 위쪽 끝 가운데, LookVector가 방 안쪽. length만큼 레이스, bowEvery마다 리본
	local function lace(face: CFrame, length: number, bowEvery: number)
		local count = math.floor(length / 0.45)
		for i = 0, count do
			Build.ball(deco, 0.5, face * CFrame.new(-length / 2 + i * length / count, -0.15, -0.05), WHITE)
		end
		local bows = math.floor(length / bowEvery)
		for i = 1, bows do
			ribbonBow(face * CFrame.new(-length / 2 + (i - 0.5) * length / bows, -0.45, -0.18), 0.8)
		end
	end
	local function faceAt(position: Vector3, normal: Vector3): CFrame
		return CFrame.lookAt(position, position + normal)
	end
	lace(faceAt(Vector3.new(0, 9, -27.98), Vector3.new(0, 0, 1)), 56.5, 7)
	for _, side in { -1, 1 } do
		lace(faceAt(Vector3.new(side * 19.48, 8, 6), Vector3.new(-side, 0, 0)), 23.5, 6)
		lace(faceAt(Vector3.new(side * 27.98, 9, -16.75), Vector3.new(-side, 0, 0)), 22.5, 7)
	end

	-- 벽 하트와 반짝이
	local function heart(face: CFrame, size: number, color: Color3)
		for _, side in { -1, 1 } do
			Build.ball(deco, 0.62 * size, face * CFrame.new(side * 0.22 * size, 0.12 * size, -0.06), color)
		end
		Build.part(deco, BLOCK, Vector3.new(0.6 * size, 0.6 * size, 0.1), face * CFrame.new(0, -0.15 * size, -0.06) * CFrame.Angles(0, 0, math.rad(45)), color)
	end
	local function sparkle(face: CFrame, size: number)
		for _, turn in { 0, 90 } do
			Build.part(deco, BLOCK, Vector3.new(0.1 * size, size, 0.05), face * CFrame.new(0, 0, -0.05) * CFrame.Angles(0, 0, math.rad(turn)), WHITE)
		end
		Build.ball(deco, 0.2 * size, face * CFrame.new(0, 0, -0.07), Color3.fromRGB(255, 244, 210))
	end
	local softPink = Color3.fromRGB(246, 178, 200)
	for _, side in { -1, 1 } do
		local wallFace = function(y: number, z: number): CFrame
			return faceAt(Vector3.new(side * 27.98, y, z), Vector3.new(-side, 0, 0))
		end
		heart(wallFace(6.3, -24.5), 1.6, WHITE)
		heart(wallFace(7.4, -21.5), 1.0, softPink)
		sparkle(wallFace(5.2, -20.8), 0.9)
		sparkle(wallFace(7.8, -26.3), 0.7)
		heart(faceAt(Vector3.new(side * 8, 7.35, -27.98), Vector3.new(0, 0, 1)), 0.8, softPink)
		sparkle(faceAt(Vector3.new(side * 10.4, 7.3, -27.98), Vector3.new(0, 0, 1)), 0.6) -- 액자와 커튼 사이
	end

	-- 카운터 주방 쪽 위 가장자리에 생크림 짜기 장식
	for i = 0, 86 do
		Build.ball(deco, 0.3, CFrame.new(-13.8 + i * 0.32, TOP + 0.06, COUNTER_Z + 1.68), WHITE)
	end

	-- 홀 앞 구석의 큰 딸기
	for _, side in { -1, 1 } do
		local base = Vector3.new(side * 21.6, 0, -26.4)
		Build.blob(deco, Vector3.new(2.2, 2.5, 2.2), CFrame.new(base + Vector3.new(0, 1.25, 0)), Color3.fromRGB(242, 104, 128))
		for i = 1, 10 do
			local angle = i * 2.4
			local y = 0.7 + (i % 4) * 0.4
			local r = 1.1 * math.sqrt(1 - ((y - 1.25) / 1.25) ^ 2)
			Build.ball(deco, 0.16, CFrame.new(base + Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r)), Color3.fromRGB(255, 232, 150))
		end
		for leaf = 1, 5 do
			local angle = leaf * math.pi * 2 / 5
			Build.part(deco, BLOCK, Vector3.new(0.9, 0.08, 0.4), CFrame.new(base + Vector3.new(math.cos(angle) * 0.35, 2.48, math.sin(angle) * 0.35)) * CFrame.Angles(0, -angle, math.rad(-12)), Color3.fromRGB(130, 196, 110))
		end
		Build.disc(deco, 0.16, 0.4, CFrame.new(base + Vector3.new(0, 2.7, 0)), Color3.fromRGB(110, 170, 96))
	end

	-- 홀 테이블: 밑에 둥근 러그, 아기 분홍 식탁보, 위에 작은 꽃병. 땡땡이는 벽에만 둔다.
	for i, spec in tables do
		local p = spec.center
		spec.top.Color = BABY
		local tint = if i % 2 == 0 then SKY else PINK
		-- 겹친 원판 윗면이 0.03 이상 떨어져야 깜빡이지 않는다
		Build.disc(deco, 8, 0.04, CFrame.new(p.X, 0.02, p.Z), tint:Lerp(WHITE, 0.25))
		Build.disc(deco, 6.6, 0.07, CFrame.new(p.X, 0.035, p.Z), WHITE)
		Build.disc(deco, 5.2, 0.1, CFrame.new(p.X, 0.05, p.Z), tint:Lerp(WHITE, 0.4))
		local vase = Build.disc(deco, 0.42, 0.6, CFrame.new(p.X, 3.1, p.Z), Color3.fromRGB(236, 246, 255), Enum.Material.Glass)
		vase.Transparency = 0.3
		Build.part(deco, CYL, Vector3.new(0.5, 0.05, 0.05), CFrame.new(p.X, 3.45, p.Z) * Build.UP, Color3.fromRGB(120, 180, 100))
		for f = 1, 3 do
			local angle = f * 2.1
			Build.ball(deco, 0.3, CFrame.new(p.X + math.cos(angle) * 0.15, 3.75 + f * 0.04, p.Z + math.sin(angle) * 0.15), sweets[(i + f) % #sweets + 1])
		end
	end

	-- 카운터 손님 쪽 가장자리를 따라 반짝이 꼬마전구
	for i = 0, 27 do
		Build.ball(deco, 0.24, CFrame.new(-13.5 + i, TOP + 0.04, COUNTER_Z - 1.62), sweets[i % #sweets + 1], NEON)
	end

	-- 카운터 위 마카롱 탑(손님 자리 사이)
	for _, x in { -8.25, 8.25 } do
		Build.disc(deco, 1.1, 0.08, CFrame.new(x, TOP + 0.04, COUNTER_Z - 0.4), WHITE)
		Build.disc(deco, 0.12, 1.0, CFrame.new(x, TOP + 0.5, COUNTER_Z - 0.4), Color3.fromRGB(232, 190, 104))
		for tier, radius in { 0.38, 0.24 } do
			local y = TOP + 0.35 + (tier - 1) * 0.5
			Build.disc(deco, radius * 2 + 0.3, 0.05, CFrame.new(x, y - 0.06, COUNTER_Z - 0.4), WHITE)
			for m = 1, 5 do
				local angle = m * math.pi * 2 / 5
				local at = CFrame.new(x + math.cos(angle) * radius, y + 0.05, COUNTER_Z - 0.4 + math.sin(angle) * radius)
				local color = sweets[(m + tier) % #sweets + 1]
				Build.disc(deco, 0.26, 0.06, at, color)
				Build.disc(deco, 0.24, 0.04, at * CFrame.new(0, 0.05, 0), WHITE)
				Build.disc(deco, 0.26, 0.06, at * CFrame.new(0, 0.1, 0), color)
			end
		end
	end

	-- 주방 옆벽 선반(병과 머그컵). 와플 기계 뚜껑(높이 6쯤)보다 위에 단다
	local shelfY = 6.6
	for _, side in { -1, 1 } do
		local x = side * 19.15
		Build.part(deco, BLOCK, Vector3.new(0.8, 0.15, 7), CFrame.new(x, shelfY, 9), WHITE)
		for _, z in { 6.2, 11.8 } do
			Build.part(deco, BLOCK, Vector3.new(0.6, 0.5, 0.12), CFrame.new(x + side * 0.1, shelfY - 0.3, z), PINK_DEEP)
		end
		for i = 0, 4 do
			local z = 6.4 + i * 1.25
			if i % 2 == 0 then
				Build.disc(deco, 0.5, 0.65, CFrame.new(x, shelfY + 0.4, z), sweets[(i + (if side > 0 then 1 else 0)) % #sweets + 1])
				Build.ball(deco, 0.32, CFrame.new(x, shelfY + 0.75, z), WHITE)
			else
				Build.disc(deco, 0.45, 0.45, CFrame.new(x, shelfY + 0.3, z), WHITE)
				Build.part(deco, BLOCK, Vector3.new(0.1, 0.25, 0.14), CFrame.new(x - side * 0.28, shelfY + 0.3, z), WHITE)
				Build.disc(deco, 0.47, 0.06, CFrame.new(x, shelfY + 0.5, z), sweets[i % #sweets + 1])
			end
		end
	end

	-- 왼쪽 벽 시계, 오른쪽 벽 하트
	Build.part(deco, CYL, Vector3.new(0.18, 2.1, 2.1), CFrame.new(-19.42, 6.6, 2), PINK_DEEP)
	Build.part(deco, CYL, Vector3.new(0.22, 1.8, 1.8), CFrame.new(-19.4, 6.6, 2), WHITE)
	Build.part(deco, BLOCK, Vector3.new(0.08, 0.7, 0.1), CFrame.new(-19.28, 6.85, 2), INK_DARK)
	Build.part(deco, BLOCK, Vector3.new(0.08, 0.1, 0.55), CFrame.new(-19.28, 6.6, 2.2), INK_DARK)
	for _, dz in { -0.32, 0.32 } do
		Build.ball(deco, 0.8, CFrame.new(19.4, 6.85, 2 + dz), PINK_DEEP)
	end
	Build.part(deco, BLOCK, Vector3.new(0.3, 0.8, 0.8), CFrame.new(19.4, 6.45, 2) * CFrame.Angles(math.rad(45), 0, 0), PINK_DEEP)
end

-- 깨끗한 조명: 아주 살짝 따뜻한 중립 흰빛, 은은한 번짐.
-- 플레이 테스트: 분홍 주변광·노을빛 보정은 누렇다고 했고, 그걸 빼고 푸른 쪽으로 맞췄더니 차갑다고 했다. 그 사이에 둔다.
-- 밝기는 처음(잘 보이던) 값에 맞추고 색만 중립으로 바꿨다. 대기(Atmosphere) 안개는 넣지 않는다: 카메라와 가게 사이에 껴서 화면이 뿌옇게 날아갔다.
local DAY_AMBIENT = Color3.fromRGB(126, 122, 120)
local DAY_TINT = Color3.fromRGB(255, 252, 248)
local function mood()
	-- 해 위치를 하루 내내 고정한다. 해가 움직이면 흰 바닥·벽에 햇빛이 정면으로 비칠 때 화면이 하얗게 날아갔다.
	Lighting.Ambient = DAY_AMBIENT
	Lighting.OutdoorAmbient = Color3.fromRGB(146, 142, 140)
	Lighting.Brightness = 1.5
	Lighting.ClockTime = DAY_CLOCK
	Lighting.GeographicLatitude = 30
	Lighting.ExposureCompensation = -0.25
	Lighting.EnvironmentSpecularScale = 0.2
	Lighting.EnvironmentDiffuseScale = 0.25 -- 하늘에서 오는 푸른 반사광을 줄인다
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "Tint"
	tint.TintColor = DAY_TINT
	tint.Saturation = 0.14
	tint.Contrast = 0.1
	tint.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.12
	bloom.Size = 18
	bloom.Threshold = 2.4
	bloom.Parent = Lighting
end

function Store.build(): Layout
	local root = Instance.new("Folder")
	root.Name = "Store"
	local deco = Instance.new("Folder")
	deco.Name = "Decor"
	deco.Parent = root

	-- 바닥: 주방은 분홍·흰 체크, 홀은 연하늘 마루
	checker(deco, Vector3.new(0, 0, 6), Vector2.new(39.5, 23.5), 4, Color3.fromRGB(252, 214, 226), WHITE)
	-- 홀 마루는 주방 바닥(z -5.75까지)과 겹치지 않게 그 앞에서 끝낸다(겹치면 경계가 깜빡인다)
	block(deco, "HallFloor", Vector3.new(57, 1, 22.75), CFrame.new(0, -0.5, -17.125), Color3.fromRGB(252, 236, 240), Enum.Material.WoodPlanks)
	City.build(root)

	-- 주방 벽: 뒷벽은 카메라 쪽이라 낮은 하늘색 벽만 둔다
	block(deco, "BackWall", Vector3.new(40, 2.2, 0.5), CFrame.new(0, 1.1, 17.75), SKY, Enum.Material.Plaster)
	block(deco, "BackTrim", Vector3.new(40.2, 0.3, 0.7), CFrame.new(0, 2.25, 17.75), WHITE)
	wall(deco, Vector3.new(0.5, 8, 23.5), Vector3.new(-19.75, 0, 6))
	wall(deco, Vector3.new(0.5, 8, 23.5), Vector3.new(19.75, 0, 6))
	for i, z in { 13, 4 } do
		for _, side in { -1, 1 } do
			lamp(deco, Vector3.new(side * 19.3, 7.2, z), if (i + side) % 2 == 0 then SKY else PINK)
		end
	end
	indoorLights(deco)

	-- 홀 벽(양옆에 문, 앞벽에 창문)과 장식
	wall(deco, Vector3.new(57, 9, 0.5), Vector3.new(0, 0, -28.25))
	for _, x in { -16, 0, 16 } do
		local glass = block(deco, "Window", Vector3.new(7, 4, 0.3), CFrame.new(x, 5, -28), Color3.fromRGB(220, 240, 252), Enum.Material.Glass)
		glass.Transparency = 0.3
		Build.part(deco, BLOCK, Vector3.new(7.6, 0.4, 0.5), CFrame.new(x, 7.1, -27.9), PINK_DEEP)
	end
	bunting(deco, Vector3.new(-26, 8.6, -27.8), Vector3.new(26, 8.6, -27.8), 26)
	local doors: { Door } = {}
	for _, side in { -1, 1 } do
		local x = side * 28.25
		wall(deco, Vector3.new(0.5, 9, 10), Vector3.new(x, 0, -23))
		wall(deco, Vector3.new(0.5, 9, 3.5), Vector3.new(x, 0, -7.25))
		-- 손님 출입구(z -18~-9): 위 벽과 양문
		block(deco, "Lintel", Vector3.new(0.5, 1.8, 9), CFrame.new(x, 8.1, -13.5), Color3.fromRGB(252, 224, 234), Enum.Material.Plaster)
		block(deco, "LintelTrim", Vector3.new(0.7, 0.3, 9.2), CFrame.new(x, 7.2, -13.5), WHITE)
		for _, hinge in { { z = -18, dir = 1 }, { z = -9, dir = -1 } } do
			table.insert(doors, doorLeaf(deco, CFrame.new(x, 0, hinge.z), hinge.dir, side))
		end
		-- 카운터 끝(x 14~16) 너머 x 16~19.75는 홀로 나가는 통로
		block(deco, "CounterEnd", Vector3.new(2, TOP, 3), CFrame.new(side * 15, TOP / 2, COUNTER_Z), PINK, Enum.Material.Plaster)
		block(deco, "HallSide", Vector3.new(8.5, TOP, 0.5), CFrame.new(side * 24, TOP / 2, -5.75), PINK, Enum.Material.Plaster)
		bigCone(deco, Vector3.new(side * 15, TOP, COUNTER_Z), if side < 0 then { "strawberry", "vanilla" } else { "mint", "chocolate" })
		plant(deco, Vector3.new(side * 25.5, 0, -25.5))
		plant(deco, Vector3.new(side * 25.5, 0, -8))
	end
	for i, p in { Vector3.new(-26, 6, -17.5), Vector3.new(-25.2, 6.8, -18.6), Vector3.new(-26.4, 7.4, -19.2) } do
		balloon(deco, p, ({ PINK_DEEP, SKY_DEEP, BUTTER })[i])
		balloon(deco, Vector3.new(-p.X, p.Y, p.Z - 6), ({ SKY_DEEP, MINT, PINK_DEEP })[i])
	end
	local tableFolder = Instance.new("Folder")
	tableFolder.Name = "Tables"
	tableFolder.Parent = root
	local tables: { TableSpec } = {}
	for i, p in { Vector3.new(-17, 0, -21), Vector3.new(-6, 0, -23), Vector3.new(6, 0, -23), Vector3.new(17, 0, -21) } do
		table.insert(tables, tableSet(tableFolder, i, p, if i % 2 == 0 then SKY else PINK))
	end
	-- 앞벽 간판
	local sign = block(deco, "Sign", Vector3.new(20, 3.2, 0.4), CFrame.new(0, 11, -27.9), WHITE)
	Build.part(deco, BLOCK, Vector3.new(20.6, 3.8, 0.3), CFrame.new(0, 11, -27.75), PINK_DEEP)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Text = "동물 디저트 카페"
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne
	title.TextColor3 = PINK_DEEP
	title.Parent = gui
	gui.Parent = sign
	for i, x in { -20, -8, 8, 20 } do
		lamp(deco, Vector3.new(x, 8.5, -27.6), if i % 2 == 0 then SKY else PINK)
	end

	-- 플레이어가 가게 밖으로 나가지 못하게 하는 투명 울타리(카운터 위 포함). 홀은 카운터 양 끝 통로로 드나든다.
	barrier(deco, Vector3.new(40, 30, 1), Vector3.new(0, 15, 18.5))
	barrier(deco, Vector3.new(1, 30, 24), Vector3.new(-20.5, 15, 6))
	barrier(deco, Vector3.new(1, 30, 24), Vector3.new(20.5, 15, 6))
	barrier(deco, Vector3.new(32, 30, 0.5), Vector3.new(0, 15, -5.9))
	for _, side in { -1, 1 } do
		barrier(deco, Vector3.new(8.5, 30, 0.5), Vector3.new(side * 24, 15, -5.75))
		barrier(deco, Vector3.new(1, 30, 9.5), Vector3.new(side * 28.75, 15, -13.5)) -- 손님 문
	end
	-- 뒷줄 뒤쪽(기구 사이와 뒤, 양옆 기구 줄 뒤 구석)은 통째로 막아서 틈에 끼지 않게 한다
	barrier(deco, Vector3.new(39, 30, 3.9), Vector3.new(0, 15, 15.55))

	-- 스테이션
	local stationFolder = Instance.new("Folder")
	stationFolder.Name = "Stations"
	stationFolder.Parent = root
	local stations: { StationSpec } = {}
	local function add(kind: string, name: string, built: Props.Built, extra: { ingredient: string?, seat: number?, lockId: string? }?)
		-- 튜토리얼 화살표가 이름·종류로 찾는다
		built.model.Name = name
		built.model:SetAttribute("Kind", kind)
		built.model.Parent = stationFolder
		-- 기구는 몸으로 부딪혀야 한다(모델 조립 도구는 기본이 충돌 없음). 위에 놓는 물건은 Items가 따로 만든다.
		for _, part in built.model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = true
			end
		end
		table.insert(stations, {
			kind = kind,
			name = name,
			built = built,
			ingredient = extra and extra.ingredient,
			seat = extra and extra.seat,
			lockId = extra and extra.lockId,
		})
	end

	-- 뒷줄: 아이스크림 기계(x -18~-12), 재료 상자 다섯(-12~8), 쟁반 더미(8~12), 아이스크림 기계(12~18).
	-- 아이스크림 기계는 양쪽 구석(양옆 기구 줄 뒤)으로 3칸씩 밀어 넣어 두 대를 둔다(손님이 몰릴 때 줄 서지 않게).
	-- 기계 앞 절반(x ±12~15)만 통로에 닿아서 프롬프트를 그쪽으로 옮긴다(기구 앞을 막으면 프롬프트가 옆 기구로 잡힌다).
	for _, side in { -1, 1 } do
		add("icemachine", "아이스크림 기계", Props.iceMachine(CFrame.new(side * 15, 0, BACK_Z) * SOUTH, -side * 1.5))
	end
	-- 이름표 방향: 첫 상자(찻잎)에서 카메라를 보는 방향으로 모두 맞춘다
	local tagFacing = (Config.Camera.position - Vector3.new(-10, TOP + 0.4, BACK_Z + 1.45)).Unit
	for i, ingredient in Config.CrateOrder do
		local x = -10 + (i - 1) * 4
		local tint = if i % 2 == 0 then PINK else SKY
		add("crate", Config.Ingredients[ingredient].name, Props.crate(CFrame.new(x, 0, BACK_Z) * SOUTH, ingredient, tint, tagFacing), { ingredient = ingredient, lockId = "ing:" .. ingredient })
	end
	add("plates", "쟁반", Props.plates(CFrame.new(10, 0, BACK_Z) * SOUTH))
	-- 쓰레기통은 가운데 섬 왼쪽, 소화기는 오른쪽(오븐 옆)에 붙인다
	add("trash", "쓰레기통", Props.trash(CFrame.new(-9.25, 0, 1.5) * WEST))
	-- 홀 쓰레기통: 카운터 양 끝 통로로 나오자마자 버리게 통로 바로 옆에 하나씩(가운데에 두면 홀이 답답했다)
	add("trash", "홀 쓰레기통", Props.trash(CFrame.new(-22.6, 0, -8.4) * EAST))
	add("trash", "홀 쓰레기통", Props.trash(CFrame.new(22.6, 0, -8.4) * WEST))
	-- 개수대(왼쪽 앞 구석, 와플 기계 줄 아래): 설거지 날(Config.Wash.day)에 열린다
	add("sink", "개수대", Props.sink(CFrame.new(-17, 0, -0.5) * EAST), { lockId = "rule:wash" })
	add("extinguisher", "소화기", Props.extinguisher(CFrame.new(8.85, 0, 1.5) * EAST))

	-- 왼쪽 벽 와플 기계, 오른쪽 벽 티 냄비(세 번째는 상점에서 연다). 뒷줄(z 11.5)에 빈틈없이 붙인다.
	for i, z in { BACK_Z - 4, BACK_Z - 8, BACK_Z - 12 } do
		add("grill", "와플 기계", Props.grill(CFrame.new(-17, 0, z) * EAST), { lockId = if i == 3 then "up:grill3" else "menu:grill" })
		add("pot", "티 냄비", Props.pot(CFrame.new(17, 0, z) * WEST), { lockId = if i == 3 then "up:pot3" else "menu:pot" })
	end

	-- 가운데 섬: 뒷줄 조합대 3 + 토핑대, 앞줄 조리대 3 + 오븐
	for i, x in { -6, -2, 2 } do
		add("board", "조합대", Props.board(CFrame.new(x, 0, 5.5) * NORTH), { lockId = if i == 3 then "up:board3" else nil })
		add("counter", "조리대", Props.counter(CFrame.new(x, 0, 1.5) * SOUTH))
	end
	add("sauce", "토핑대", Props.sauce(CFrame.new(6, 0, 5.5) * NORTH), { lockId = "menu:sauce" })
	add("oven", "오븐", Props.oven(CFrame.new(6, 0, 1.5) * SOUTH), { lockId = "menu:oven" })

	-- 주문 카운터와 손님 자리(자리마다 쟁반을 내려놓는 레이스 받침)
	local counter = Instance.new("Model")
	counter.Name = "OrderCounter"
	counter.Parent = stationFolder
	block(counter, "CounterBody", Vector3.new(28, TOP - 0.3, 3), CFrame.new(0, (TOP - 0.3) / 2, COUNTER_Z), BABY)
	for i = 0, 13 do
		Build.part(counter, BLOCK, Vector3.new(0.9, TOP - 0.6, 0.08), CFrame.new(-13 + i * 2, (TOP - 0.3) / 2, COUNTER_Z - 1.53), WHITE)
	end
	-- 상판은 양 끝 블록(x ±14 바깥)과 겹치지 않게 28 폭
	block(counter, "CounterTop", Vector3.new(28, 0.3, 3.4), CFrame.new(0, TOP - 0.15, COUNTER_Z), WHITE)
	local seats: { Seat } = {}
	-- 손님 자리 받침: 진한 색은 형광처럼 보여서 연한 파스텔로
	local matColors = {
		Color3.fromRGB(255, 214, 226), -- 연핑크
		Color3.fromRGB(208, 234, 250), -- 연하늘
		Color3.fromRGB(255, 240, 200), -- 연노랑
		Color3.fromRGB(210, 242, 226), -- 연민트
		Color3.fromRGB(234, 222, 248), -- 연보라
	}
	for i, x in SEAT_X do
		local m = Instance.new("Model")
		m.Name = `Seat{i}`
		local mat = Build.disc(m, 2.8, 0.06, CFrame.new(x, TOP + 0.03, COUNTER_Z), WHITE)
		Build.disc(m, 2.2, 0.12, CFrame.new(x, TOP + 0.06, COUNTER_Z), matColors[i])
		-- 주문 종(장식)
		Build.ball(m, 0.5, CFrame.new(x + 1.3, TOP + 0.2, COUNTER_Z - 1.0), Color3.fromRGB(232, 190, 104), Enum.Material.Metal)
		-- 프롬프트는 주방 쪽 카운터 가장자리(플레이어가 서서 손님을 바라보는 곳)
		add("seat", `{i}번 손님`, { model = m, base = mat, slots = { CFrame.new(x, TOP + 0.12, COUNTER_Z) }, prompt = Vector3.new(x, TOP + 0.4, COUNTER_Z + 1.3) }, { seat = i })
		table.insert(seats, { index = i, stand = CFrame.lookAt(Vector3.new(x, 0, STAND_Z), Vector3.new(x, 0, 0)) })
	end

	local customers = Instance.new("Folder")
	customers.Name = "Customers"
	customers.Parent = root
	local items = Instance.new("Folder")
	items.Name = "Items"
	items.Parent = root

	decorate(deco, tables)
	mood()
	root.Parent = workspace
	return {
		root = root,
		customers = customers,
		items = items,
		stations = stations,
		seats = seats,
		tables = tables,
		doors = doors,
		lane = { entry = Vector3.new(-31, 0, -14), exit = Vector3.new(31, 0, -14), z = -14 },
		spawn = CFrame.lookAt(Vector3.new(0, 2.2, 10.5), Vector3.new(0, 2.2, 0)),
	}
end

-- 영업하면 문을 열고, 마감하면 닫는다
function Store.setDoors(layout: Layout, open: boolean)
	for _, door in layout.doors do
		TweenService:Create(door.panel, TweenInfo.new(0.9, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = if open then door.open else door.closed }):Play()
	end
end

return Store
