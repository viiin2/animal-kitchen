--!strict
-- 창 위쪽 장식 띠: 아기 분홍 바탕에 하얀 땡땡이, 아랫단 레이스(반원), 가운데 분홍 리본.
-- 아침·밤 창, 상점, 동물 고르기, MVP 창이 같이 쓴다(클라이언트 화면 전용). 띠는 내용 뒤(ZIndex 0)에 깔린다.
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

return UiDeco
