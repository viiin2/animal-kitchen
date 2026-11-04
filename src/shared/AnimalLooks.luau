--!strict
-- 동물 인형 모양: 큰 머리, 반짝이는 큰 눈, 볼터치, 팔다리와 신발, 셔츠·바지, 동물마다 다른 소품, 꼬리.
-- 서버(손님·플레이어 캐릭터)와 클라이언트(동물 고르기 창 미리보기)가 같이 쓴다. 발밑이 원점, 앞은 -Z.
-- robux 0은 처음부터 쓸 수 있고, 나머지는 게임패스(Robux)로 사람마다 연다(Avatars). 코인은 상점 업그레이드에만 쓴다.
-- 동물마다 작은 능력(perks)이 있다.
local Build = require(script.Parent.Build)

-- 동물마다 작은 능력(0.12 = 12%). 자기 행동에만 붙는다: 이동, 내가 낸 디저트의 팁, 내가 올린 디저트가 익는 시간,
-- 내가 만든 아이스크림이 녹는 시간, F 길게(조합·토핑·치우기·불 끄기) 시간.
export type Perks = { speed: number, tip: number, cook: number, melt: number, hold: number }

export type Look = {
	name: string,
	robux: number, -- 0이면 처음부터. 아니면 게임패스(Robux)로 연다
	pass: number, -- Creator Dashboard에서 만든 게임패스 id. 0이면 아직 없음(Studio에서만 무료로 열어 시험)
	perkText: string,
	perks: { speed: number?, tip: number?, cook: number?, melt: number?, hold: number? },
	fur: Color3,
	muzzle: Color3, -- 입 주변
	ear: string, -- cat | rabbit | bear | dog | pig
	inner: Color3, -- 귀 안쪽(강아지는 늘어진 귀 색)
	limbs: Color3?, -- 손·귀 털이 몸과 다를 때(판다)
	marking: string?, -- stripes(이마 줄무늬) | spot(한쪽 눈 얼룩)
	markColor: Color3?,
	shirt: Color3,
	pants: Color3,
	shoes: Color3,
	extra: string?, -- scarf | flower | bow
	extraColor: Color3?,
	patches: boolean?, -- 판다 눈 무늬
}

export type Outfit = {
	chef: boolean, -- 플레이어: 요리사 모자와 앞치마
	shirt: Color3?, -- 손님은 옷 색을 바꿔서 같은 동물도 달라 보이게 한다
}

local AnimalLooks = {}

local rgb = Color3.fromRGB

AnimalLooks.list = {
	{ name = "주황 고양이", robux = 0, pass = 0, perkText = "내가 낸 디저트 팁 +25%", perks = { tip = 0.25 }, fur = rgb(250, 198, 152), muzzle = rgb(255, 242, 228), ear = "cat", inner = rgb(252, 196, 200), marking = "stripes", markColor = rgb(238, 164, 116), shirt = rgb(255, 236, 170), pants = rgb(150, 200, 238), shoes = rgb(255, 250, 246), extra = "scarf", extraColor = rgb(120, 196, 236) },
	{ name = "토끼", robux = 0, pass = 0, perkText = "이동 속도 +12%", perks = { speed = 0.12 }, fur = rgb(252, 248, 244), muzzle = rgb(255, 255, 255), ear = "rabbit", inner = rgb(250, 186, 196), shirt = rgb(250, 180, 204), pants = rgb(255, 250, 246), shoes = rgb(246, 150, 180), extra = "flower", extraColor = rgb(255, 214, 96) },
	{ name = "곰", robux = 0, pass = 0, perkText = "내가 올린 디저트가 12% 빨리 익음", perks = { cook = 0.12 }, fur = rgb(198, 152, 120), muzzle = rgb(248, 228, 208), ear = "bear", inner = rgb(242, 196, 188), shirt = rgb(184, 230, 206), pants = rgb(166, 134, 114), shoes = rgb(250, 246, 240), extra = "scarf", extraColor = rgb(236, 110, 120) },
	{ name = "돼지", robux = 49, pass = 0, perkText = "내가 만든 아이스크림이 60% 늦게 녹음", perks = { melt = 0.6 }, fur = rgb(250, 196, 200), muzzle = rgb(246, 168, 178), ear = "pig", inner = rgb(240, 160, 170), shirt = rgb(170, 214, 246), pants = rgb(255, 250, 246), shoes = rgb(130, 170, 220), extra = "scarf", extraColor = rgb(130, 196, 240) },
	{ name = "강아지", robux = 79, pass = 0, perkText = "F 길게(조합·토핑·치우기) 35% 빨리", perks = { hold = 0.35 }, fur = rgb(246, 224, 194), muzzle = rgb(255, 246, 234), ear = "dog", inner = rgb(212, 164, 132), marking = "spot", markColor = rgb(212, 164, 132), shirt = rgb(246, 140, 140), pants = rgb(90, 110, 150), shoes = rgb(255, 250, 246), extra = "bow", extraColor = rgb(130, 196, 240) },
	{ name = "회색 고양이", robux = 99, pass = 0, perkText = "익히기 22% 빨리 + 이동 +6%", perks = { cook = 0.22, speed = 0.06 }, fur = rgb(204, 202, 222), muzzle = rgb(244, 242, 250), ear = "cat", inner = rgb(248, 196, 208), marking = "stripes", markColor = rgb(164, 160, 186), shirt = rgb(208, 186, 240), pants = rgb(152, 142, 172), shoes = rgb(246, 150, 180), extra = "bow", extraColor = rgb(240, 130, 170) },
	{ name = "판다", robux = 149, pass = 0, perkText = "이동 +10%, F 길게 20% 빨리, 팁 +20%", perks = { speed = 0.1, hold = 0.2, tip = 0.2 }, fur = rgb(252, 252, 250), muzzle = rgb(255, 255, 255), ear = "bear", inner = rgb(110, 104, 114), limbs = rgb(72, 68, 78), shirt = rgb(250, 176, 200), pants = rgb(255, 250, 246), shoes = rgb(50, 48, 54), extra = "flower", extraColor = rgb(250, 160, 190), patches = true },
} :: { Look }

local BLOCK = Enum.PartType.Block
local CYL = Enum.PartType.Cylinder
-- 천(Fabric) 재질은 이 플레이스에서 거의 까맣게 나와서(구 메시에 입히면 더 심함) 매끈한 재질로 인형 느낌을 낸다
local SOFT = Enum.Material.SmoothPlastic
local INK = rgb(52, 40, 48)
local WHITE = rgb(255, 255, 255)
local BLUSH = rgb(255, 168, 188)
local EYE = rgb(80, 52, 50) -- 새까만 눈보다 부드러운 짙은 갈색
local RIBBON = rgb(246, 160, 186)
local LACE = rgb(255, 252, 250)
local PINK_NOSE = rgb(240, 130, 150)
local BROWN_NOSE = rgb(90, 62, 60)
local PATCH = rgb(72, 68, 78)
local APRON = rgb(255, 248, 240)
local APRON_TRIM = rgb(246, 150, 180)

local HEAD_Y = 3.65
local HEAD = Vector3.new(2.9, 2.45, 2.35)

function AnimalLooks.get(index: number): Look
	return AnimalLooks.list[(index - 1) % #AnimalLooks.list + 1]
end

-- 플레이어 속성 AnimalIndex(아무 값이나)로 능력을 꺼낸다. 없는 능력은 0.
function AnimalLooks.perksFor(index: unknown): Perks
	local look = if typeof(index) == "number" then AnimalLooks.list[index] else nil
	if not look then
		return { speed = 0, tip = 0, cook = 0, melt = 0, hold = 0 }
	end
	local p = look.perks
	return { speed = p.speed or 0, tip = p.tip or 0, cook = p.cook or 0, melt = p.melt or 0, hold = p.hold or 0 }
end

-- 동물을 그린다. origin이 발밑(기본은 원점). 머리 파트를 돌려준다.
function AnimalLooks.paint(model: Model, look: Look, outfit: Outfit?, origin: CFrame?): Part
	local o = origin or CFrame.identity
	local function at(x: number, y: number, z: number): CFrame
		return o * CFrame.new(x, y, z)
	end
	local function tilt(x: number, y: number, z: number, rz: number): CFrame
		return o * CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(rz))
	end
	local chef = outfit ~= nil and outfit.chef
	local shirt = (outfit and outfit.shirt) or look.shirt
	local paws = look.limbs or look.fur

	-- 다리·신발
	for _, side in { -1, 1 } do
		Build.blob(model, Vector3.new(0.66, 0.4, 0.86), at(side * 0.42, 0.2, -0.08), look.shoes, SOFT)
		Build.disc(model, 0.58, 0.8, at(side * 0.42, 0.72, 0), look.pants, SOFT)
	end
	-- 몸통: 셔츠 + 바지 허리
	Build.blob(model, Vector3.new(1.8, 1.7, 1.4), at(0, 1.8, 0), shirt, SOFT)
	Build.blob(model, Vector3.new(1.74, 0.8, 1.36), at(0, 1.2, 0), look.pants, SOFT)
	-- 팔: 소매 + 둥근 손
	for _, side in { -1, 1 } do
		Build.blob(model, Vector3.new(0.58, 1.1, 0.58), tilt(side * 1.0, 1.95, 0, side * 18), shirt, SOFT)
		Build.ball(model, 0.56, at(side * 1.17, 1.38, -0.04), paws, SOFT)
	end

	-- 꼬리(카메라는 주로 뒤에서 본다)
	if look.ear == "cat" then
		Build.blob(model, Vector3.new(0.3, 1.3, 0.3), o * CFrame.new(0.35, 1.55, 0.85) * CFrame.Angles(math.rad(35), 0, math.rad(-25)), look.fur, SOFT)
	elseif look.ear == "dog" then
		Build.blob(model, Vector3.new(0.34, 0.9, 0.34), o * CFrame.new(0, 1.5, 0.8) * CFrame.Angles(math.rad(40), 0, 0), look.fur, SOFT)
	else
		Build.ball(model, if look.ear == "rabbit" then 0.62 elseif look.ear == "pig" then 0.32 else 0.46, at(0, 1.3, 0.72), paws, SOFT)
	end

	-- 머리
	local head = Build.blob(model, HEAD, at(0, HEAD_Y, 0), look.fur, SOFT)
	if look.ear == "pig" then
		Build.part(model, CYL, Vector3.new(0.3, 0.8, 0.8), at(0, 3.3, -1.2) * CFrame.Angles(0, math.rad(90), 0), look.muzzle, SOFT)
		for _, side in { -1, 1 } do
			Build.blob(model, Vector3.new(0.14, 0.2, 0.06), at(side * 0.15, 3.3, -1.36), BROWN_NOSE)
		end
		Build.blob(model, Vector3.new(0.26, 0.08, 0.06), at(0, 2.98, -1.0), INK)
	else
		Build.blob(model, Vector3.new(1.2, 0.78, 0.5), at(0, 3.27, -1.0), look.muzzle, SOFT)
		local soft = look.ear == "cat" or look.ear == "rabbit"
		Build.blob(model, Vector3.new(0.34, 0.24, 0.2), at(0, 3.47, -1.24), if soft then PINK_NOSE else BROWN_NOSE)
		-- ω 입
		for _, side in { -1, 1 } do
			Build.part(model, BLOCK, Vector3.new(0.2, 0.05, 0.05), tilt(side * 0.08, 3.18, -1.25, side * -30), INK)
		end
	end
	-- 반짝이는 큰 눈과 볼터치
	for _, side in { -1, 1 } do
		local x = side * 0.62
		if look.patches then
			Build.blob(model, Vector3.new(0.9, 1.05, 0.2), tilt(x, 3.84, -0.97, side * -20), PATCH, SOFT)
		end
		Build.blob(model, Vector3.new(0.5, 0.6, 0.2), at(x, 3.82, -1.02), EYE)
		Build.blob(model, Vector3.new(0.2, 0.2, 0.08), at(x + 0.08, 3.94, -1.12), WHITE)
		Build.blob(model, Vector3.new(0.09, 0.09, 0.06), at(x - 0.08, 3.7, -1.12), WHITE)
		local cheek = Build.blob(model, Vector3.new(0.6, 0.34, 0.1), at(side * 1.0, 3.36, -0.82) * CFrame.Angles(0, math.rad(-35 * side), 0), BLUSH)
		cheek.Transparency = 0.05
	end

	-- 무늬: 고양이 이마 줄무늬, 강아지 한쪽 눈 얼룩
	local markColor = look.markColor or look.inner
	if look.marking == "stripes" then
		for i, x in { -0.32, 0, 0.32 } do
			Build.blob(model, Vector3.new(0.16, 0.5 - math.abs(x) * 0.4, 0.1), at(x, 4.62 - (if i == 2 then 0 else 0.04), -0.66) * CFrame.Angles(math.rad(50), 0, 0), markColor)
		end
	elseif look.marking == "spot" then
		Build.blob(model, Vector3.new(0.95, 0.95, 0.2), tilt(0.62, 3.9, -0.97, 15), markColor)
	end

	-- 귀
	local earFur = look.limbs or look.fur
	for _, side in { -1, 1 } do
		if look.ear == "cat" then
			local turn = math.rad(45 - side * 8)
			Build.part(model, BLOCK, Vector3.new(0.9, 0.9, 0.4), at(side * 0.88, 4.72, 0.1) * CFrame.Angles(0, 0, turn), earFur, SOFT)
			Build.part(model, BLOCK, Vector3.new(0.5, 0.5, 0.1), at(side * 0.88, 4.78, -0.12) * CFrame.Angles(0, 0, turn), look.inner, SOFT)
		elseif look.ear == "rabbit" then
			Build.blob(model, Vector3.new(0.62, 2.0, 0.36), tilt(side * 0.72, 5.5, 0.15, side * -14), earFur, SOFT)
			Build.blob(model, Vector3.new(0.32, 1.5, 0.1), tilt(side * 0.72, 5.5, -0.05, side * -14), look.inner, SOFT)
		elseif look.ear == "dog" then
			Build.blob(model, Vector3.new(0.7, 1.5, 0.4), tilt(side * 1.5, 3.85, 0.05, side * 14), look.inner, SOFT)
		elseif look.ear == "pig" then
			local turn = o * CFrame.new(side * 0.95, 4.6, -0.1) * CFrame.Angles(math.rad(-20), 0, 0) * CFrame.Angles(0, 0, math.rad(45))
			Build.part(model, BLOCK, Vector3.new(0.66, 0.66, 0.3), turn, earFur, SOFT)
			Build.part(model, BLOCK, Vector3.new(0.36, 0.36, 0.1), turn * CFrame.new(0, 0, -0.16), look.inner, SOFT)
		else
			Build.ball(model, 0.85, at(side * 1.02, 4.62, 0.1), earFur, SOFT)
			Build.part(model, CYL, Vector3.new(0.08, 0.5, 0.5), at(side * 1.02, 4.62, -0.33) * CFrame.Angles(0, math.rad(90), 0), look.inner, SOFT)
		end
	end

	-- 소품
	local extra = look.extra
	local extraColor = look.extraColor or WHITE
	if extra == "scarf" then
		Build.blob(model, Vector3.new(2.0, 0.42, 1.6), at(0, 2.55, 0), extraColor, SOFT)
		Build.blob(model, Vector3.new(0.4, 0.8, 0.16), tilt(0.35, 2.15, -0.72, 12), extraColor, SOFT)
	elseif extra == "flower" then
		local center = at(-0.9, 4.3, -0.72)
		for i = 1, 5 do
			local angle = i * math.pi * 2 / 5
			Build.ball(model, 0.3, center * CFrame.new(math.cos(angle) * 0.2, math.sin(angle) * 0.2, 0), extraColor, SOFT)
		end
		Build.ball(model, 0.22, center * CFrame.new(0, 0, -0.08), rgb(246, 150, 90))
	elseif extra == "bow" then
		-- 귀 밑 머리핀 리본
		local center = at(-1.05, 4.15, -0.7)
		for _, side in { -1, 1 } do
			Build.blob(model, Vector3.new(0.6, 0.45, 0.25), center * CFrame.new(side * 0.3, 0, 0) * CFrame.Angles(0, 0, math.rad(side * 15)), extraColor, SOFT)
		end
		Build.ball(model, 0.26, center * CFrame.new(0, 0, -0.04), Build.shade(extraColor, 0.12), SOFT)
	end

	-- 레이스 칼라(스카프를 한 동물은 빼고)
	if extra ~= "scarf" then
		for i = 1, 14 do
			local angle = i * math.pi * 2 / 14
			Build.ball(model, 0.3, at(math.cos(angle) * 0.86, 2.52, math.sin(angle) * 0.7), LACE, SOFT)
		end
	end

	-- 요리사: 분홍 리본 두른 모자, 프릴 앞치마, 등 뒤 큰 리본(카메라가 주로 뒤에서 본다)
	if chef then
		local narrow = look.ear == "rabbit" or look.ear == "cat"
		local band = if narrow then 1.0 else 1.25
		Build.disc(model, band, 0.4, at(0, 4.98, 0.1), RIBBON, SOFT)
		Build.blob(model, if narrow then Vector3.new(1.15, 0.9, 1.2) else Vector3.new(1.7, 1.0, 1.5), at(0, 5.55, 0.1), WHITE, SOFT)
		local hatBow = at(0.28, 5.0, 0.1 - band / 2 - 0.05)
		for _, side in { -1, 1 } do
			Build.blob(model, Vector3.new(0.34, 0.26, 0.12), hatBow * CFrame.new(side * 0.17, 0, 0) * CFrame.Angles(0, 0, math.rad(side * 15)), RIBBON, SOFT)
		end
		Build.ball(model, 0.14, hatBow * CFrame.new(0, 0, -0.03), Build.shade(RIBBON, 0.1), SOFT)
		-- 앞치마: 아랫단 레이스, 하트 주머니
		Build.blob(model, Vector3.new(1.35, 1.25, 0.16), at(0, 1.55, -0.66), APRON, SOFT)
		for i = -3, 3 do
			Build.ball(model, 0.22, at(i * 0.19, 0.96, -0.68), LACE, SOFT)
		end
		local pocket = at(0.22, 1.36, -0.76)
		for _, side in { -1, 1 } do
			Build.ball(model, 0.17, pocket * CFrame.new(side * 0.07, 0.04, 0), APRON_TRIM, SOFT)
		end
		Build.part(model, BLOCK, Vector3.new(0.17, 0.17, 0.05), pocket * CFrame.new(0, -0.04, 0) * CFrame.Angles(0, 0, math.rad(45)), APRON_TRIM, SOFT)
		Build.blob(model, Vector3.new(1.86, 0.16, 1.46), at(0, 1.95, 0), APRON_TRIM, SOFT)
		-- 등 뒤 큰 리본
		local backBow = at(0, 1.98, 0.8)
		for _, side in { -1, 1 } do
			Build.blob(model, Vector3.new(0.62, 0.44, 0.22), backBow * CFrame.new(side * 0.32, 0.04, 0) * CFrame.Angles(0, 0, math.rad(side * 18)), RIBBON, SOFT)
			Build.blob(model, Vector3.new(0.18, 0.56, 0.08), backBow * CFrame.new(side * 0.14, -0.34, 0.02) * CFrame.Angles(0, 0, math.rad(side * -14)), RIBBON, SOFT)
		end
		Build.ball(model, 0.24, backBow * CFrame.new(0, 0, 0.04), Build.shade(RIBBON, 0.1), SOFT)
	end
	return head
end

-- 파산했을 때(파산 결과창 인형): 꼬질꼬질 먼지 빛, 덧대 기운 옷(하얀 바늘땀), 반창고, 얼룩, 눈물 자국, 처진 눈썹, 엉엉 우는 입.
-- paint로 그린 모델에 덧붙인다(look·origin은 paint에 준 것과 같게). 요리사 차림(앞치마)을 기준으로 자리를 잡았다.
local DUST = rgb(150, 128, 110)
local SMUDGE = rgb(118, 92, 76)
local TEAR = rgb(150, 205, 245)
local BANDAGE = rgb(250, 222, 190)

function AnimalLooks.shabby(model: Model, look: Look, origin: CFrame?)
	local o = origin or CFrame.identity
	local function at(x: number, y: number, z: number): CFrame
		return o * CFrame.new(x, y, z)
	end
	local function tilt(x: number, y: number, z: number, rz: number): CFrame
		return o * CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(rz))
	end
	-- 꼬질꼬질: 모든 색을 먼지 빛으로 조금 탁하게
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 1 then
			part.Color = part.Color:Lerp(DUST, 0.22)
		end
	end
	-- 덧댄 천 + 네 변에 하얀 바늘땀
	local function patch(cframe: CFrame, w: number, h: number, color: Color3)
		Build.part(model, BLOCK, Vector3.new(w, h, 0.05), cframe, color, SOFT)
		for _, sign in { -1, 1 } do
			for _, k in { -1, 1 } do
				Build.part(model, BLOCK, Vector3.new(0.03, 0.11, 0.03), cframe * CFrame.new(k * w / 4, sign * h / 2, -0.035), WHITE)
				Build.part(model, BLOCK, Vector3.new(0.11, 0.03, 0.03), cframe * CFrame.new(sign * w / 2, k * h / 4, -0.035), WHITE)
			end
		end
	end
	patch(tilt(-0.32, 1.72, -0.79, 12), 0.52, 0.46, rgb(255, 214, 120)) -- 앞치마
	patch(tilt(-1.08, 2.0, -0.31, -18), 0.3, 0.32, rgb(150, 200, 240)) -- 소매
	patch(tilt(0.42, 0.62, -0.32, -8), 0.3, 0.28, rgb(240, 150, 160)) -- 무릎
	-- 반창고(이마 옆)
	local band = tilt(0.55, 4.3, -0.9, -28)
	Build.part(model, BLOCK, Vector3.new(0.62, 0.2, 0.06), band, BANDAGE, SOFT)
	Build.part(model, BLOCK, Vector3.new(0.18, 0.14, 0.03), band * CFrame.new(0, 0, -0.035), Build.shade(BANDAGE, 0.12), SOFT)
	-- 얼룩(반투명 흙 자국)
	for _, spot in {
		{ cf = at(-0.95, 3.05, -0.72) * CFrame.Angles(0, math.rad(35), 0), size = Vector3.new(0.42, 0.26, 0.08) },
		{ cf = at(0.38, 1.28, -0.77), size = Vector3.new(0.32, 0.2, 0.06) },
		{ cf = at(-0.45, 0.86, -0.31), size = Vector3.new(0.22, 0.16, 0.05) },
	} do
		local smudge = Build.blob(model, spot.size, spot.cf, SMUDGE)
		smudge.Transparency = 0.35
	end
	-- 눈물 자국 · 처진 눈썹(안쪽 끝이 올라감)
	for _, side in { -1, 1 } do
		local stream = Build.blob(model, Vector3.new(0.15, 0.5, 0.06), at(side * 0.62, 3.42, -1.08), TEAR)
		stream.Transparency = 0.15
		Build.part(model, BLOCK, Vector3.new(0.42, 0.09, 0.08), tilt(side * 0.62, 4.28, -0.9, -side * 20), INK)
	end
	-- 엉엉 벌린 입 + 혀
	local mouthZ = if look.ear == "pig" then -1.0 else -1.2
	Build.blob(model, Vector3.new(0.36, 0.26, 0.08), at(0, 3.02, mouthZ), INK)
	Build.blob(model, Vector3.new(0.2, 0.1, 0.04), at(0, 2.96, mouthZ - 0.03), rgb(240, 130, 150))
end

-- 고르기 창 미리보기용 모델(Root 가운데가 몸 가운데). 플레이어 모습(요리사 차림)으로 그린다.
function AnimalLooks.preview(index: number): Model
	local model = Build.model("AnimalPreview", Vector3.new(3, 6.6, 2.6))
	AnimalLooks.paint(model, AnimalLooks.get(index), { chef = true }, CFrame.new(0, -3.3, 0))
	return model
end

return AnimalLooks
