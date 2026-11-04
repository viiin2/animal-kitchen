--!strict
-- 효과음(Config.Sounds). 서버가 보내는 것(Remotes.Sfx: 조합·토핑·불·불 끄기·치우기·버리기·사기)과
-- 이 클라이언트가 직접 알아채는 것을 튼다:
--   코인 띠롱(Remotes.Earned), 집기·내려놓기(속성 Holding), 손님 주문 딩동·화남(손님 Mood),
--   카운트다운·영업 시작·성공·실패(상태), 버튼 클릭(화면의 모든 버튼).
-- 소리는 2D로 튼다(위에서 내려다보는 카메라라 3D 소리는 멀어서 작게 들린다).
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local sfxEvent = remotes:WaitForChild(Config.Remotes.Sfx) :: RemoteEvent
local earnedEvent = remotes:WaitForChild(Config.Remotes.Earned) :: RemoteEvent
local stateEvent = remotes:WaitForChild(Config.Remotes.State) :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local customers = workspace:WaitForChild("Store"):WaitForChild("Customers")

local folder = Instance.new("Folder")
folder.Name = "KitchenSfx"
folder.Parent = SoundService
local templates: { [string]: Sound } = {}
for name, def in Config.Sounds do
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = def.id
	sound.Volume = def.volume
	sound.PlaybackSpeed = def.speed
	sound.Parent = folder
	templates[name] = sound
end

-- 같은 소리가 겹쳐도 끊기지 않게 복사해서 튼다
local function play(name: string)
	local template = templates[name]
	if not template then
		return
	end
	local sound = template:Clone()
	sound.Parent = folder
	sound:Play()
	Debris:AddItem(sound, 4)
end

sfxEvent.OnClientEvent:Connect(function(name: unknown)
	if typeof(name) == "string" then
		play(name)
	end
end)

-- 코인 띠롱
earnedEvent.OnClientEvent:Connect(function()
	play("coin")
	task.delay(0.09, play, "coinHigh")
end)

-- 집기·내려놓기(녹는 중 같은 이름 바뀜은 빼고, 손이 비었다 찼다만)
local lastHolding = player:GetAttribute("Holding")
player:GetAttributeChangedSignal("Holding"):Connect(function()
	local now = player:GetAttribute("Holding")
	if now ~= nil and lastHolding == nil then
		play("pick")
	elseif now == nil and lastHolding ~= nil then
		play("drop")
	end
	lastHolding = now
end)

-- 손님: 주문하면 딩동, 지쳐서 가면 낮은 소리
local function watch(model: Instance)
	if not model:IsA("Model") or model:GetAttribute("Companion") == true then
		return
	end
	model:GetAttributeChangedSignal("Mood"):Connect(function()
		local mood = model:GetAttribute("Mood")
		if mood == "waiting" then
			play("order")
		elseif mood == "angry" then
			play("angry")
		end
	end)
end
customers.ChildAdded:Connect(watch)
for _, child in customers:GetChildren() do
	watch(child)
end

-- 하루: 카운트다운 째깍, 영업 시작, 정산 성공·실패
local lastPhase: string? = nil
stateEvent.OnClientEvent:Connect(function(state: { phase: string, endsAt: number, passed: boolean, report: { earned: number }? })
	local phase = state.phase
	if phase ~= lastPhase then
		if phase == "countdown" then
			-- 3·2·1이 보일 때만 째깍(그 전에는 날짜 커튼이 지나간다)
			local left = math.max(0, state.endsAt - workspace:GetServerTimeNow())
			for i = 0, math.floor(left) - 1 do
				if math.floor(left) - i <= Config.CountdownSeconds then
					task.delay(left - math.floor(left) + i, play, "tick")
				end
			end
		elseif phase == "open" then
			play("start")
		elseif phase == "night" and lastPhase == "open" then
			-- 가운데서 "오늘 번 돈"이 올라가는 동안 짤랑짤랑, 정산 창이 뜰 때 성공·실패
			if state.report and state.report.earned > 0 then
				for i = 0, 5 do
					task.delay(0.3 + i * 0.25, play, "coin")
				end
			end
			task.delay(Config.NightIntroSeconds, play, if state.passed then "win" else "lose")
		end
	end
	lastPhase = phase
end)

-- 화면 버튼 누를 때 딸깍
local function hookButton(object: Instance)
	if object:IsA("GuiButton") then
		object.Activated:Connect(function()
			play("click")
		end)
	end
end
playerGui.DescendantAdded:Connect(hookButton)
for _, object in playerGui:GetDescendants() do
	hookButton(object)
end
