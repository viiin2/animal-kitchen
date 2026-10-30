--!strict
-- 파트를 조립해 모델을 만드는 공통 도구. 음식(FoodModels)·주방 기구(Props)·손님(Critters)이 같이 쓴다.
local Build = {}

-- 원기둥의 축(X)을 세로로 세우는 회전
Build.UP = CFrame.Angles(0, 0, math.rad(90))

function Build.part(parent: Instance, shape: Enum.PartType, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, reflectance: number?): Part
	local part = Instance.new("Part")
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Reflectance = reflectance or 0
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Parent = parent
	return part
end

-- 세운 원기둥(접시·냄비·그릇): 지름, 높이, 가운데 위치
function Build.disc(parent: Instance, diameter: number, height: number, cframe: CFrame, color: Color3, material: Enum.Material?, reflectance: number?): Part
	return Build.part(parent, Enum.PartType.Cylinder, Vector3.new(height, diameter, diameter), cframe * Build.UP, color, material, reflectance)
end

function Build.ball(parent: Instance, diameter: number, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	return Build.part(parent, Enum.PartType.Ball, Vector3.new(diameter, diameter, diameter), cframe, color, material)
end

-- 타원체(넓적한 머리, 통통한 몸, 길쭉한 귀): Block 파트에 구 메시를 씌운다. 메시는 파트 크기를 따른다.
-- 동물 인형에만 쓴다(Model:ScaleTo로 키우는 음식 모델에는 쓰지 않는다). 재질은 매끈한 플라스틱만 제대로 보인다.
function Build.blob(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = Build.part(parent, Enum.PartType.Block, size, cframe, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- 빈 모델과 투명한 Root(PrimaryPart). Root 크기가 그 물건이 차지하는 부피다.
function Build.model(name: string, rootSize: Vector3): Model
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = rootSize
	root.CFrame = CFrame.identity
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root
	return model
end

-- 움직이는 모델: 모든 파트를 Root에 용접하고 Root만 고정한다. 이후 PivotTo로 통째로 옮긴다.
function Build.rig(model: Model): BasePart
	local root = model.PrimaryPart :: BasePart
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = descendant
			weld.Parent = descendant
			descendant.Anchored = false
			descendant.Massless = true
		end
	end
	root.Anchored = true
	return root
end

-- 땡땡이: face(면 가운데, LookVector = 면이 바라보는 쪽)에 width×height 크기로 흰 원을 엇갈린 줄로 붙인다.
-- skip(원 자리)이 true면 그 자리는 비운다(창문·액자 등).
function Build.polka(parent: Instance, face: CFrame, width: number, height: number, spacing: number, size: number, color: Color3, skip: ((Vector3) -> boolean)?)
	local cols = math.max(1, math.floor(width / spacing))
	local rows = math.max(1, math.floor(height / (spacing * 0.8)))
	for r = 0, rows - 1 do
		local v = -height / 2 + (r + 0.5) * height / rows
		local shift = if r % 2 == 0 then 0.25 else 0.75
		for c = 0, cols - 1 do
			local u = -width / 2 + (c + shift) * width / cols
			local at = face * CFrame.new(u, v, -0.02)
			if not (skip and skip(at.Position)) then
				-- 원기둥 축(X)을 면이 바라보는 쪽(-Z)으로 돌려 납작한 원으로
				Build.part(parent, Enum.PartType.Cylinder, Vector3.new(0.04, size, size), at * CFrame.Angles(0, math.rad(90), 0), color)
			end
		end
	end
end

function Build.shade(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

return Build
