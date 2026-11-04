--!strict
-- 창 위쪽 장식 띠: 아기 분홍 바탕에 하얀 땡땡이, 아랫단 레이스(반원), 가운데 분홍 리본.
-- 아침·밤 창, 상점, 동물 고르기, MVP 창이 같이 쓴다(클라이언트 화면 전용). 띠는 내용 뒤(ZIndex 0)에 깔린다.
-- 창 말랑 팝(popIn·popOut)도 여기 있다.
local TweenService = game:GetService("TweenService")

local UiDeco = {}

local BABY = Color3.fromRGB(248, 214, 226)
local RIBBON = Color3.fromRGB(240, 150, 178)
local WHITE = Color3.new(1, 1, 1)

local function circle(parent: Instance, size: number, position: UDim2, color: Color3, transparency: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = position
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.ZIndex = 0
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = f
	f.Parent = parent
	return f
end

-- window 위쪽에 높이 height짜리 띠. inset은 창의 UIPadding(가로, 세로)만큼 바깥으로 넓힌다. radius는 창 모서리 둥글기.
function UiDeco.header(window: GuiObject, height: number, radius: number, inset: Vector2?)
	local pad = inset or Vector2.zero
	local band = Instance.new("Frame")
	band.Name = "DecoHeader"
	band.Position = UDim2.fromOffset(-pad.X, -pad.Y)
	band.Size = UDim2.new(1, pad.X * 2, 0, height)
	band.BackgroundColor3 = BABY
	band.BorderSizePixel = 0
	band.ZIndex = 0
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, radius)
	round.Parent = band
	band.Parent = window
	-- 아래쪽 모서리는 각지게(위만 둥글게)
	local square = Instance.new("Frame")
	square.Position = UDim2.new(0, 0, 0.5, 0)
	square.Size = UDim2.fromScale(1, 0.5)
	square.BackgroundColor3 = BABY
	square.BorderSizePixel = 0
	square.ZIndex = 0
	square.Parent = band

	-- 하얀 땡땡이(엇갈린 두 줄)
	for row = 0, 1 do
		for i = 0, 23 do
			local x = (i + (if row == 0 then 0.25 else 0.75)) / 24
			circle(band, 7, UDim2.new(x, 0, 0, 10 + row * 14), WHITE, 0.15)
		end
	end
	-- 아랫단 레이스: 반쯤 걸친 하얀 반원
	for i = 0, 44 do
		circle(band, 16, UDim2.new(i / 44, 0, 1, 0), WHITE)
	end
	-- 가운데 위 리본
	for _, side in { -1, 1 } do
		local loop = Instance.new("Frame")
		loop.AnchorPoint = Vector2.new(0.5, 0.5)
		loop.Position = UDim2.new(0.5, side * 13, 0, 0)
		loop.Size = UDim2.fromOffset(26, 17)
		loop.Rotation = side * 15
		loop.BackgroundColor3 = RIBBON
		loop.BorderSizePixel = 0
		loop.ZIndex = 0
		local loopRound = Instance.new("UICorner")
		loopRound.CornerRadius = UDim.new(0.5, 0)
		loopRound.Parent = loop
		loop.Parent = band
	end
	circle(band, 11, UDim2.new(0.5, 0, 0, 0), Color3.fromRGB(226, 128, 160))
end

-- ── 창 말랑 팝 ──
-- 창의 UIScale(화면 크기 맞춤용)을 잠깐 줄였다가 통 튀어 원래 크기로(열기), 쏙 줄인 뒤 done(닫기).
-- 화면 크기에 맞춘 값은 fit으로 넣는다: 팝 도중에 값을 바로 바꾸면 크기가 덜컹거려서, 팝이 끝난 뒤에 맞춘다.
-- 닫는 중에 다시 열면 닫기는 취소된다.
local popSeq: { [UIScale]: number } = {}
local closing: { [UIScale]: boolean } = {}
local popping: { [UIScale]: boolean } = {}
local rest: { [UIScale]: number } = {} -- 팝이 끝나면 돌아갈 크기(화면 맞춤 값)

function UiDeco.fit(scale: UIScale, value: number)
	rest[scale] = value
	if not popping[scale] then
		scale.Scale = value
	end
end

function UiDeco.popIn(scale: UIScale, target: number?)
	local goal = target or rest[scale] or scale.Scale
	rest[scale] = goal
	local seq = (popSeq[scale] or 0) + 1
	popSeq[scale] = seq
	closing[scale] = nil
	popping[scale] = true
	scale.Scale = goal * 0.7
	local tween = TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = goal })
	tween.Completed:Once(function()
		if popSeq[scale] == seq then
			popping[scale] = nil
			scale.Scale = rest[scale] or goal
		end
	end)
	tween:Play()
end

function UiDeco.popOut(scale: UIScale, done: () -> ())
	if closing[scale] then
		return
	end
	local seq = (popSeq[scale] or 0) + 1
	popSeq[scale] = seq
	closing[scale] = true
	popping[scale] = true
	local base = rest[scale] or scale.Scale
	local tween = TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = base * 0.6 })
	tween.Completed:Once(function()
		if popSeq[scale] == seq then
			closing[scale] = nil
			popping[scale] = nil
			done()
			scale.Scale = rest[scale] or base -- 다음에 열 때를 위해 되돌린다(이미 숨겨져서 안 보인다)
		end
	end)
	tween:Play()
end

-- 닫히는 중인지(그 사이 다시 보여야 하면 popIn을 부른다)
function UiDeco.isClosing(scale: UIScale): boolean
	return closing[scale] == true
end

return UiDeco
