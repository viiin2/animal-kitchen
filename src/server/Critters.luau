--!strict
-- 동물 모델 만들기. 생김새는 AnimalLooks(공용)에 있다.
-- customer(): 손님. Root(발밑 가운데)에 용접해서 PivotTo로 옮긴다. 앞은 -Z(LookVector).
-- character(i): 플레이어 캐릭터. 요리사 모자와 앞치마를 두르고, Humanoid로 걷는다.
--   몸은 HumanoidRootPart에 Motor6D("Bob")로 매달아 클라이언트(Animals)가 걸을 때 통통 튀게 한다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Build = require(ReplicatedStorage.Shared.Build)
local AnimalLooks = require(ReplicatedStorage.Shared.AnimalLooks)

local Critters = {}

Critters.count = #AnimalLooks.list

local rng = Random.new()

function Critters.lookName(index: number): string
	return AnimalLooks.get(index).name
end

-- 손님은 동물도 옷 색도 무작위라 같은 동물이 와도 달라 보인다
local SHIRTS = {
	Color3.fromRGB(255, 236, 170),
	Color3.fromRGB(184, 230, 206),
	Color3.fromRGB(170, 214, 246),
	Color3.fromRGB(250, 180, 204),
	Color3.fromRGB(208, 186, 240),
	Color3.fromRGB(255, 200, 150),
	Color3.fromRGB(246, 140, 140),
}

function Critters.customer(): Model
	local model = Build.model("Customer", Vector3.new(2.4, 0.2, 2.4))
	local look = AnimalLooks.list[rng:NextInteger(1, #AnimalLooks.list)]
	AnimalLooks.paint(model, look, { chef = false, shirt = SHIRTS[rng:NextInteger(1, #SHIRTS)] })
	Build.rig(model)
	return model
end

-- 플레이어 캐릭터. 발밑이 원점, HumanoidRootPart는 그 위 2스터드(HipHeight 1).
function Critters.character(index: number): Model
	local model = Instance.new("Model")
	model.Name = "Animal"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1.6)
	root.CFrame = CFrame.new(0, 2, 0)
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model
	model.PrimaryPart = root

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(1, 1, 1)
	body.CFrame = root.CFrame
	body.Transparency = 1
	body.CanCollide = false
	body.CanQuery = false
	body.Massless = true
	body.Parent = model
	local bob = Instance.new("Motor6D")
	bob.Name = "Bob"
	bob.Part0 = root
	bob.Part1 = body
	bob.Parent = root

	local head = AnimalLooks.paint(model, AnimalLooks.get(index), { chef = true })
	head.Name = "Head"

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part ~= root and part ~= body then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = part
			weld.Parent = part
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
		end
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 1
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	return model
end

return Critters
