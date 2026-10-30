--!strict
-- 동물 캐릭터가 걸을 때 통통 튀고 살짝 기우뚱하게 한다(모든 플레이어 캐릭터, 이 화면에서만 그린다).
-- 캐릭터 몸은 HumanoidRootPart에 Motor6D "Bob"으로 매달려 있다(Critters.character).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local phase: { [Model]: number } = {}

RunService.RenderStepped:Connect(function(dt: number)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local bob = root and root:FindFirstChild("Bob")
		if character and root and root:IsA("BasePart") and bob and bob:IsA("Motor6D") then
			local velocity = root.AssemblyLinearVelocity
			local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			local moving = math.clamp(speed / 12, 0, 1)
			local t = (phase[character] or 0) + dt * (6 + 8 * moving)
			phase[character] = t
			local hop = math.abs(math.sin(t)) * 0.45 * moving + math.sin(t * 0.5) * 0.04
			local tilt = math.sin(t) * 0.1 * moving
			bob.Transform = CFrame.new(0, hop, 0) * CFrame.Angles(0, 0, tilt)
		end
	end
	for character in phase do
		if not character.Parent then
			phase[character] = nil
		end
	end
end)
