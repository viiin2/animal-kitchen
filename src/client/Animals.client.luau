--!strict
-- 동물들의 몸짓(이 화면에서만 그린다). 몸은 Root(손님)·HumanoidRootPart(플레이어)에 Motor6D "Bob"으로 매달려 있고(Critters),
-- 여기서 Bob.Transform만 바꾼다. 판정·위치는 그대로 서버가 정한다.
--
-- 플레이어 동물
--   걸을 때 통통 튀고 기우뚱 · 가만히 있으면 숨쉬듯 들썩이고 가끔 두리번
--   F 길게 누르는 중·아이스크림 기계 쓰는 중(플레이어 속성 Working)이면 요리하듯 몸을 흔들흔들
--   물건을 집거나 내려놓으면(속성 Holding이 바뀌면) 꾹 눌렸다 펴짐
--   손님에게 내면(Remotes.Earned의 낸 사람) 폴짝 뛰며 한 바퀴 · 밤 정산이 흑자면 다 같이 빙글빙글 승리 춤
-- 손님
--   걸을 때 통통 · 기다릴 때 숨쉬기, 인내심이 1/4 아래면 부들부들
--   받으면(Mood happy) 폴짝폴짝 · 화나서 나갈 때(Mood angry) 앞으로 숙이고 쿵쿵 · 테이블에서 먹을 때 냠냠
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local earnedEvent = remotes:WaitForChild(Config.Remotes.Earned) :: RemoteEvent
local stateEvent = remotes:WaitForChild(Config.Remotes.State) :: RemoteEvent
local customersFolder = workspace:WaitForChild("Store"):WaitForChild("Customers")

local JUMP_SECONDS = 0.5
local DIP_SECONDS = 0.28
local DANCE_SECONDS = 2.6
local HAPPY_SECONDS = 1.1

type Motion = {
	t: number, -- 걷기·숨쉬기 박자
	last: Vector3?, -- 지난 프레임 위치(손님은 고정 파트라 속도가 없어서 위치 차이로 잰다)
	speed: number,
	yaw: number, -- 두리번(지금 고개 방향)
	lookYaw: number,
	lookUntil: number,
	nextLook: number,
	dipAt: number,
	jumpAt: number,
	happyAt: number,
	mood: string,
}

local motions: { [Model]: Motion } = {}
local danceAt = -math.huge
local lastPhase = ""

local function motionOf(model: Model): Motion
	local m = motions[model]
	if not m then
		m = {
			t = math.random() * 10,
			last = nil,
			speed = 0,
			yaw = 0,
			lookYaw = 0,
			lookUntil = 0,
			nextLook = os.clock() + 2 + math.random() * 4,
			dipAt = -math.huge,
			jumpAt = -math.huge,
			happyAt = -math.huge,
			mood = "",
		}
		motions[model] = m
	end
	return m
end

-- 0→1→0 한 번 솟았다 내려오는 곡선
local function arc(elapsed: number, duration: number): number
	if elapsed < 0 or elapsed > duration then
		return 0
	end
	return math.sin(math.pi * elapsed / duration)
end

-- 위치 차이로 잰 수평 속도(부드럽게)
local function measure(m: Motion, position: Vector3, dt: number)
	local last = m.last
	if last and dt > 0 then
		local step = Vector3.new(position.X - last.X, 0, position.Z - last.Z).Magnitude / dt
		m.speed += (math.min(step, 30) - m.speed) * math.min(1, dt * 10)
	end
	m.last = position
end

-- 가만히 있을 때 가끔 고개(몸)를 좌우로 돌려 두리번
local function lookAround(m: Motion, now: number, dt: number, idle: boolean): number
	if idle and now >= m.nextLook then
		m.lookYaw = (math.random() - 0.5) * 1.1
		m.lookUntil = now + 0.8 + math.random() * 0.6
		m.nextLook = now + 3 + math.random() * 5
	end
	local target = if idle and now < m.lookUntil then m.lookYaw else 0
	m.yaw += (target - m.yaw) * math.min(1, dt * 6)
	return m.yaw
end

local function playerPose(player: Player, root: BasePart, m: Motion, now: number, dt: number): CFrame
	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moving = math.clamp(speed / 12, 0, 1)
	local working = player:GetAttribute("Working") ~= nil
	m.t += dt * (if working then 14 else 6 + 8 * moving)
	local t = m.t
	local x, y, lean, yaw, tilt = 0, 0, 0, 0, 0
	if working and moving < 0.3 then
		-- 요리 중: 좌우로 흔들흔들 + 콩콩
		x = math.sin(t) * 0.12
		y = math.abs(math.sin(t)) * 0.12
		tilt = math.sin(t) * 0.12
		lean = -0.08
	else
		-- 걷기 통통 + 서 있으면 숨쉬기
		y = math.abs(math.sin(t)) * 0.45 * moving + math.sin(now * 2.2) * 0.05 * (1 - moving)
		tilt = math.sin(t) * 0.1 * moving
	end
	yaw = lookAround(m, now, dt, moving < 0.1 and not working)
	-- 집기·내려놓기: 꾹 눌렸다가 살짝 튀어 오른다
	local dip = now - m.dipAt
	if dip >= 0 and dip < DIP_SECONDS then
		y += -0.3 * arc(dip, DIP_SECONDS * 0.6) + 0.18 * arc(dip - DIP_SECONDS * 0.6, DIP_SECONDS * 0.4)
		lean += 0.1 * arc(dip, DIP_SECONDS * 0.6)
	end
	-- 서빙 성공: 폴짝 뛰며 한 바퀴
	local jump = now - m.jumpAt
	if jump >= 0 and jump < JUMP_SECONDS then
		y += 1.3 * arc(jump, JUMP_SECONDS)
		yaw += math.pi * 2 * (jump / JUMP_SECONDS)
	end
	-- 흑자 밤: 빙글빙글 승리 춤
	local dance = now - danceAt
	if dance >= 0 and dance < DANCE_SECONDS then
		y += math.abs(math.sin(dance * 9)) * 0.6
		yaw += dance * 7
		tilt += math.sin(dance * 9) * 0.15
	end
	return CFrame.new(x, y, 0) * CFrame.Angles(lean, yaw, tilt)
end

local function customerPose(model: Model, root: BasePart, m: Motion, now: number, dt: number): CFrame
	measure(m, root.Position, dt)
	local moving = math.clamp(m.speed / 8, 0, 1)
	local mood = model:GetAttribute("Mood")
	if typeof(mood) == "string" and mood ~= m.mood then
		if mood == "happy" then
			m.happyAt = now
		end
		m.mood = mood
	end
	local angry = mood == "angry"
	m.t += dt * (if angry then 5 else 6 + 8 * moving)
	local t = m.t
	local x, y, lean, yaw, tilt = 0, 0, 0, 0, 0
	if angry and moving > 0.2 then
		-- 화나서 나간다: 앞으로 숙이고 쿵쿵
		y = math.abs(math.sin(t)) * 0.3
		lean = -0.18
		tilt = math.sin(t) * 0.16
	elseif moving > 0.05 then
		y = math.abs(math.sin(t)) * 0.4 * moving
		tilt = math.sin(t) * 0.1 * moving
	elseif mood == "dining" then
		-- 냠냠: 콩콩 끄덕
		y = math.abs(math.sin(now * 7)) * 0.08
		lean = math.sin(now * 7) * 0.06
	else
		y = math.sin(now * 2.2 + m.t * 0.1) * 0.05
		yaw = lookAround(m, now, dt, mood == "waiting")
	end
	-- 인내심이 1/4 아래거나 막 화났으면 부들부들
	local orderedAt = model:GetAttribute("OrderedAt")
	local expiresAt = model:GetAttribute("ExpiresAt")
	local nervous = false
	if mood == "waiting" and typeof(orderedAt) == "number" and typeof(expiresAt) == "number" and expiresAt > orderedAt then
		local left = (expiresAt - workspace:GetServerTimeNow()) / (expiresAt - orderedAt)
		nervous = left < 0.25
	end
	if nervous or (angry and moving <= 0.2) then
		x += math.sin(now * 55) * 0.07
		tilt += math.sin(now * 47) * 0.04
	end
	-- 받았다! 폴짝폴짝
	local happy = now - m.happyAt
	if happy >= 0 and happy < HAPPY_SECONDS then
		y += 0.9 * math.abs(math.sin(math.pi * happy / (HAPPY_SECONDS / 2)))
	end
	return CFrame.new(x, y, 0) * CFrame.Angles(lean, yaw, tilt)
end

local function bobOf(root: Instance?): Motor6D?
	local bob = root and root:FindFirstChild("Bob")
	return if bob and bob:IsA("Motor6D") then bob else nil
end

RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local bob = bobOf(root)
		if character and root and root:IsA("BasePart") and bob then
			bob.Transform = playerPose(player, root, motionOf(character), now, dt)
		end
	end
	for _, model in customersFolder:GetChildren() do
		if model:IsA("Model") then
			local root = model.PrimaryPart
			local bob = bobOf(root)
			if root and bob then
				bob.Transform = customerPose(model, root, motionOf(model), now, dt)
			end
		end
	end
	for model in motions do
		if not model.Parent then
			motions[model] = nil
		end
	end
end)

-- 집기·내려놓기: 플레이어 속성 Holding이 바뀔 때마다 꾹
local function watchPlayer(player: Player)
	player:GetAttributeChangedSignal("Holding"):Connect(function()
		local character = player.Character
		if character then
			motionOf(character).dipAt = os.clock()
		end
	end)
end
Players.PlayerAdded:Connect(watchPlayer)
for _, player in Players:GetPlayers() do
	watchPlayer(player)
end

-- 서빙 성공: 낸 사람이 폴짝
earnedEvent.OnClientEvent:Connect(function(_position: Vector3, _amount: number, _combo: number, serverId: number?)
	if typeof(serverId) ~= "number" then
		return
	end
	local server = Players:GetPlayerByUserId(serverId)
	local character = server and server.Character
	if character then
		motionOf(character).jumpAt = os.clock()
	end
end)

-- 밤 정산이 흑자면 "오늘 번 돈"이 끝나고 정산 창이 뜰 때 다 같이 승리 춤
stateEvent.OnClientEvent:Connect(function(state: { phase: string, passed: boolean })
	if state.phase == "night" and lastPhase == "open" and state.passed then
		danceAt = os.clock() + Config.NightIntroSeconds
	end
	lastPhase = state.phase
end)
