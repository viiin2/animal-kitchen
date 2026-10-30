--!strict
-- 홀 테이블(Config.DineIn.day부터): 손님이 디저트를 받아 앉아서 먹고, 떠나면 빈 그릇이 남는다.
-- 지저분한 테이블은 플레이어가 E로 빈 그릇을 집어 치워야 다음 손님이 앉는다(그릇은 쓰레기통이나, 설거지 날부터는 개수대로).
-- 손님 움직임은 Customers가, 손에 쥐여 주는 것은 Stations(Main이 onClear에 잇는다)가 맡는다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(ReplicatedStorage.Shared.Build)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)
local Store = require(script.Parent.Store)

type Table = {
	spec: Store.TableSpec,
	state: string, -- free | taken | dirty
	seat: number, -- 앉은(앉았던) 의자 번호
	prompt: ProximityPrompt,
	shown: Model?, -- 먹는 디저트 또는 빈 그릇
}

local Tables = {}

-- 빈 그릇을 손에 쥐여 준다. 쥐여 줬으면 true(손이 차 있으면 false). Main이 Stations.giveDishes를 넣는다.
Tables.onClear = function(_player: Player): boolean
	return false
end

local tables: { Table } = {}
local rng = Random.new()

local function show(t: Table, model: Model?)
	local old = t.shown
	if old then
		old:Destroy()
	end
	t.shown = model
	if model then
		model.Parent = t.spec.model
	end
end

-- 다 먹은 자리: 빈 컵, 크림 묻은 접시, 부스러기, 구겨진 냅킨
local function mess(at: CFrame): Model
	local model = Build.model("Mess", Vector3.new(1.6, 0.6, 1.6))
	local plate = Build.disc(model, 1.3, 0.08, CFrame.new(0, -0.26, 0), Color3.fromRGB(255, 252, 250))
	plate.Name = "Plate"
	Build.ball(model, 0.3, CFrame.new(0.2, -0.16, 0.1), Color3.fromRGB(255, 255, 255))
	local cup = Build.disc(model, 0.5, 0.6, CFrame.new(-0.55, 0.0, -0.35), Color3.fromRGB(236, 246, 255))
	cup.Transparency = 0.35
	Build.disc(model, 0.44, 0.12, CFrame.new(-0.55, -0.24, -0.35), Color3.fromRGB(214, 172, 132))
	for i = 1, 6 do
		local angle = i * 1.9
		Build.part(model, Enum.PartType.Block, Vector3.new(0.1, 0.06, 0.1), CFrame.new(math.cos(angle) * 0.5, -0.27, math.sin(angle) * 0.45), Color3.fromRGB(214, 170, 110))
	end
	Build.ball(model, 0.34, CFrame.new(0.55, -0.12, -0.4), Color3.fromRGB(250, 214, 226))
	model:PivotTo(at)
	return model
end

-- 켜고 끄기는 클라이언트(Prompts)가 바라보는 기구만 켠다. 서버는 쓸 수 있는지만 알려 준다.
local function refresh(t: Table)
	t.prompt:SetAttribute("On", t.state == "dirty")
end

function Tables.init(layout: Store.Layout)
	for _, spec in layout.tables do
		local point = Instance.new("Attachment")
		point.Name = "PromptPoint"
		point.Parent = spec.top
		point.WorldPosition = spec.center + Vector3.new(0, 3.3, 0)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = "테이블"
		prompt.ActionText = "빈 그릇 치우기"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt:SetAttribute("On", false)
		prompt.Parent = point
		local t: Table = { spec = spec, state = "free", seat = 1, prompt = prompt, shown = nil }
		prompt.Triggered:Connect(function(player: Player)
			if t.state == "dirty" and Tables.onClear(player) then
				t.state = "free"
				show(t, nil)
				refresh(t)
			end
		end)
		table.insert(tables, t)
	end
end

-- 빈 테이블 하나를 맡는다. (테이블 번호, 앉을 자리 발밑 CFrame)
function Tables.reserve(): (number?, CFrame?)
	local free = {}
	for i, t in tables do
		if t.state == "free" then
			table.insert(free, i)
		end
	end
	if #free == 0 then
		return nil, nil
	end
	local index = free[rng:NextInteger(1, #free)]
	local t = tables[index]
	t.state = "taken"
	t.seat = rng:NextInteger(1, #t.spec.seats)
	return index, t.spec.seats[t.seat]
end

-- 앉아서 먹는 동안 테이블 위에 디저트를 놓는다
function Tables.serve(index: number, kind: string, state: string, spec: Config.IceSpec?)
	local t = tables[index]
	if not t then
		return
	end
	local food = FoodModels.build(kind, state, 0, spec)
	local root = food.PrimaryPart :: BasePart
	food:PivotTo(t.spec.food[t.seat] * CFrame.new(0, root.Size.Y / 2 - 0.08, 0))
	show(t, food)
end

-- 손님이 떠나면 지저분해진다
function Tables.leave(index: number)
	local t = tables[index]
	if not t or t.state ~= "taken" then
		return
	end
	t.state = "dirty"
	show(t, mess(t.spec.food[t.seat] * CFrame.new(0, 0.22, 0)))
	refresh(t)
end

-- 맡았지만 앉지 않고 가면(영업 끝) 다시 비운다
function Tables.release(index: number)
	local t = tables[index]
	if t and t.state == "taken" then
		t.state = "free"
		show(t, nil)
		refresh(t)
	end
end

-- 하루를 시작하거나 끝낼 때 모두 깨끗하게
function Tables.reset()
	for _, t in tables do
		t.state = "free"
		show(t, nil)
		refresh(t)
	end
end

function Tables.dirtyCount(): number
	local count = 0
	for _, t in tables do
		if t.state == "dirty" then
			count += 1
		end
	end
	return count
end

return Tables
