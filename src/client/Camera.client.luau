--!strict
-- 카메라 시점 세 가지(Config.CameraModes). C 키나 화면 오른쪽 카메라 버튼(Hud)으로 차례로 바꾼다. 둘 다 LocalPlayer 속성 CameraMode만 바꾼다.
--   따라가기(기본): 내 캐릭터를 위에서 따라가며 카운터 쪽을 본다. 마우스 휠로 확대·축소.
--   뒤에서 보기: 캐릭터 뒤통수 위에서 캐릭터가 보는 쪽을 본다. 이때는 조작도 캐릭터 기준(W 앞, S 뒤, A·D 제자리 돌기)이다.
--     카메라 기준 조작 그대로면 옆으로 갈 때마다 카메라가 따라 돌아서 빙글빙글 돈다. 마우스는 묶지 않아 창 버튼을 누를 수 있다.
--   전체 보기: 주방 뒤 위에서 카운터 앞 손님까지 한눈에 보는 고정 시점. 화면 비율이 바뀌어도 가로 폭(halfWidth)이 다 들어온다.
-- (1인칭은 시야가 낮고 화면이 느리게 돌고, 마우스가 묶여 아이스크림 창을 못 눌러서 뺐다.)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local FOLLOW_OFFSET = Vector3.new(0, 26, 19) -- 캐릭터에서 카메라까지(전체 보기와 비슷한 각도)
local FOLLOW_AHEAD = Vector3.new(0, 0, -4) -- 카운터 쪽을 조금 더 보이게
local FOLLOW_FOV = 50
local FOLLOW_SPEED = 12 -- 클수록 빨리 따라간다
local ZOOM_MIN, ZOOM_MAX = 0.55, 1.5

local BEHIND_BACK = 8.5 -- 뒤로
local BEHIND_UP = 6.5 -- 발밑에서 위로(뒤통수 위)
local BEHIND_LOOK = 7 -- 이만큼 앞을 본다
local BEHIND_FOV = 70
local BEHIND_SPEED = 14
local TURN_SPEED = math.rad(200) -- A·D로 도는 빠르기(초당)

local player = Players.LocalPlayer
local view = Config.Camera
local distance = (view.position - view.focus).Magnitude
local zoom = 1
local current = "" -- 지난 프레임의 시점
local smoothed: CFrame? = nil

if player:GetAttribute("CameraMode") == nil then
	player:SetAttribute("CameraMode", Config.CameraModes[1].id)
end

local function fixedFieldOfView(camera: Camera): number
	local size = camera.ViewportSize
	local aspect = size.X / math.max(size.Y, 1)
	local vertical = 2 * math.deg(math.atan(view.halfWidth / distance / aspect))
	return math.max(view.minFieldOfView, vertical)
end

local function humanoidOf(character: Model?): Humanoid?
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

-- 뒤에서 보기: 캐릭터 기준 조작으로 바꾸고 되돌리기
local function setTankControls(on: boolean)
	player.DevComputerMovementMode = if on then Enum.DevComputerMovementMode.Scriptable else Enum.DevComputerMovementMode.UserChoice
	local humanoid = humanoidOf(player.Character)
	if humanoid then
		humanoid.AutoRotate = not on
		if not on then
			humanoid:Move(Vector3.zero)
		end
	end
end

local function keyDown(...: Enum.KeyCode): boolean
	for _, key in { ... } do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

local function tankStep(dt: number, root: BasePart, humanoid: Humanoid)
	humanoid.AutoRotate = false
	if UserInputService:GetFocusedTextBox() then
		humanoid:Move(Vector3.zero)
		return
	end
	local turn = (if keyDown(Enum.KeyCode.A, Enum.KeyCode.Left) then 1 else 0) - (if keyDown(Enum.KeyCode.D, Enum.KeyCode.Right) then 1 else 0)
	local forward = (if keyDown(Enum.KeyCode.W, Enum.KeyCode.Up) then 1 else 0) - (if keyDown(Enum.KeyCode.S, Enum.KeyCode.Down) then 1 else 0)
	if turn ~= 0 then
		root.CFrame = root.CFrame * CFrame.Angles(0, turn * TURN_SPEED * dt, 0)
	end
	local look = root.CFrame.LookVector
	humanoid:Move(Vector3.new(look.X, 0, look.Z).Unit * forward * (if forward < 0 then 0.7 else 1))
	if keyDown(Enum.KeyCode.Space) then
		humanoid.Jump = true
	end
end

-- 벽이 카메라를 가리면 캐릭터 쪽으로 당긴다
local function unblocked(from: Vector3, to: Vector3, character: Model): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(from, to - from, params)
	if hit then
		return hit.Position + (from - to).Unit * 0.6
	end
	return to
end

RunService:BindToRenderStep("KitchenCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local mode = player:GetAttribute("CameraMode")
	local next = if mode == "behind" or mode == "fixed" then mode else "follow"
	if next ~= current then
		if current == "behind" then
			setTankControls(false)
		elseif next == "behind" then
			setTankControls(true)
		end
		current = next
		smoothed = nil
	end
	camera.CameraType = Enum.CameraType.Scriptable
	if current == "fixed" then
		camera.FieldOfView = fixedFieldOfView(camera)
		camera.CFrame = CFrame.lookAt(view.position, view.focus)
		return
	end

	local character = player.Character
	local root = character and character.PrimaryPart
	local goal: CFrame
	if current == "behind" and character and root then
		local humanoid = humanoidOf(character)
		if humanoid then
			tankStep(dt, root, humanoid)
		end
		local look = root.CFrame.LookVector
		local facing = Vector3.new(look.X, 0, look.Z).Unit
		local feet = root.Position - Vector3.new(0, 2, 0)
		local head = feet + Vector3.new(0, 4.5, 0)
		local eye = unblocked(head, feet - facing * BEHIND_BACK + Vector3.new(0, BEHIND_UP, 0), character)
		goal = CFrame.lookAt(eye, feet + facing * BEHIND_LOOK + Vector3.new(0, 2, 0))
		camera.FieldOfView = BEHIND_FOV
	else
		local target = if root then Vector3.new(root.Position.X, 0, root.Position.Z) else view.focus
		goal = CFrame.lookAt(target + FOLLOW_OFFSET * zoom, target + FOLLOW_AHEAD)
		camera.FieldOfView = FOLLOW_FOV
	end
	local speed = if current == "behind" then BEHIND_SPEED else FOLLOW_SPEED
	local from = smoothed or goal
	local now = from:Lerp(goal, math.min(1, dt * speed))
	smoothed = now
	camera.CFrame = now
end)

-- 캐릭터가 새로 생기면(동물 바꾸기·리스폰) 뒤에서 보기 조작을 다시 건다
player.CharacterAdded:Connect(function(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid and humanoid:IsA("Humanoid") and current == "behind" then
		humanoid.AutoRotate = false
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or input.KeyCode ~= Enum.KeyCode.C then
		return
	end
	local modes = Config.CameraModes
	local index = 1
	for i, mode in modes do
		if mode.id == player:GetAttribute("CameraMode") then
			index = i
		end
	end
	player:SetAttribute("CameraMode", modes[index % #modes + 1].id)
end)

-- 따라가기에서 마우스 휠로 확대·축소
UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel or current ~= "follow" then
		return
	end
	zoom = math.clamp(zoom - input.Position.Z * 0.08, ZOOM_MIN, ZOOM_MAX)
end)
