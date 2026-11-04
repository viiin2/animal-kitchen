--!strict
-- 주방 기구 몸짓(이 화면에서만 그린다). 서버(Stations)가 기구 모델에 다는 신호만 본다(태그 "Station").
--   속성 Cook = "cooking": 익는 동안 들썩들썩 + 김 모락모락
--               "danger": 곧 탈 때 덜덜덜 + 회색 연기, "burnt": 탔을 때 더 덜덜 + 검은 연기
--   속성 DoneAt: 조합·토핑·설거지가 끝나면 하얀 뿅 + 반짝반짝 + "✨"이 톡 튀어 오른다
-- 기구는 움직이지 않으므로 처음 위치를 기억해 두고 흔든 뒤 그 자리로 돌려놓는다.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

type Fx = {
	model: Model,
	home: CFrame,
	top: Attachment,
	steam: ParticleEmitter,
	smoke: ParticleEmitter,
	burst: ParticleEmitter,
	puff: ParticleEmitter,
	shaking: boolean,
}

local stations: { [Model]: Fx } = {}

local function emitter(parent: Attachment, color: Color3, rate: number, size: NumberSequence, transparency: NumberSequence, speed: NumberRange, life: NumberRange): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Rate = rate
	e.Size = size
	e.Transparency = transparency
	e.Speed = speed
	e.Lifetime = life
	e.SpreadAngle = Vector2.new(18, 18)
	e.EmissionDirection = Enum.NormalId.Top
	e.LightInfluence = 0
	e.Enabled = false
	e.Parent = parent
	return e
end

local function setup(model: Instance)
	if not model:IsA("Model") or stations[model] then
		return
	end
	local home = model:GetPivot()
	local cframe, size = model:GetBoundingBox()
	local top = Instance.new("Attachment")
	top.Name = "KitchenFx"
	top.WorldPosition = cframe.Position + Vector3.new(0, size.Y / 2 + 0.2, 0)
	top.Parent = workspace.Terrain

	local steam = emitter(top, Color3.new(1, 1, 1), 5, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 1.4),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	}), NumberRange.new(1.5, 2.5), NumberRange.new(1, 1.6))
	local smoke = emitter(top, Color3.fromRGB(120, 112, 112), 12, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 2),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	}), NumberRange.new(2, 3.5), NumberRange.new(1.2, 2))
	-- 반짝: 별빛이 사방으로 튀었다가 사라진다
	local burst = emitter(top, Color3.fromRGB(255, 236, 160), 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	}), NumberSequence.new(0), NumberRange.new(5, 9), NumberRange.new(0.5, 0.8))
	burst.Texture = SPARKLE
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Rotation = NumberRange.new(0, 360)
	burst.RotSpeed = NumberRange.new(-200, 200)
	burst.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 170)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 210)),
	})
	-- 하얀 뿅(동그랗게 커지며 사라짐)
	local puff = emitter(top, Color3.new(1, 1, 1), 0, NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 3.2),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	}), NumberRange.new(0), NumberRange.new(0.35))

	local fx: Fx = { model = model, home = home, top = top, steam = steam, smoke = smoke, burst = burst, puff = puff, shaking = false }
	stations[model] = fx

	local function onCook()
		local cook = model:GetAttribute("Cook")
		steam.Enabled = cook == "cooking" or cook == "done"
		steam.Rate = if cook == "cooking" then 6 else 2
		smoke.Enabled = cook == "danger" or cook == "burnt"
		smoke.Color = ColorSequence.new(if cook == "burnt" then Color3.fromRGB(70, 64, 64) else Color3.fromRGB(150, 142, 142))
	end
	model:GetAttributeChangedSignal("Cook"):Connect(onCook)
	onCook()

	model:GetAttributeChangedSignal("DoneAt"):Connect(function()
		puff:Emit(1)
		burst:Emit(16)
		-- "✨"이 톡 튀어 올랐다 사라진다
		local gui = Instance.new("BillboardGui")
		gui.Adornee = top
		gui.Size = UDim2.new(2.2, 0, 2.2, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.5)
		label.Size = UDim2.fromScale(0.3, 0.3)
		label.TextScaled = true
		label.Text = "✨"
		label.Parent = gui
		gui.Parent = top
		TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1) }):Play()
		TweenService:Create(gui, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 1.6, 0) }):Play()
		task.delay(0.5, function()
			TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end)
		Debris:AddItem(gui, 1)
	end)
end

local function teardown(model: Instance)
	local fx = stations[model :: Model]
	if fx then
		fx.top:Destroy()
		stations[model :: Model] = nil
	end
end

CollectionService:GetInstanceAddedSignal("Station"):Connect(setup)
CollectionService:GetInstanceRemovedSignal("Station"):Connect(teardown)
for _, model in CollectionService:GetTagged("Station") do
	setup(model)
end

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	for model, fx in stations do
		local cook = model:GetAttribute("Cook")
		local offset: CFrame? = nil
		if cook == "cooking" then
			-- 들썩들썩(위로 콩콩 + 살짝 기우뚱)
			offset = CFrame.new(0, math.abs(math.sin(t * 9)) * 0.08, 0) * CFrame.Angles(0, 0, math.sin(t * 9) * 0.025)
		elseif cook == "danger" or cook == "burnt" then
			-- 덜덜덜(탔으면 더 세게)
			local power = if cook == "burnt" then 1.6 else 1
			offset = CFrame.new(math.sin(t * 50) * 0.06 * power, math.abs(math.sin(t * 31)) * 0.05 * power, 0)
				* CFrame.Angles(0, 0, math.sin(t * 43) * 0.04 * power)
		end
		if offset then
			model:PivotTo(fx.home * offset)
			fx.shaking = true
		elseif fx.shaking then
			model:PivotTo(fx.home)
			fx.shaking = false
		end
	end
end)
