--!strict
-- 로비 서버(체험의 시작 장소): 광장을 짓고, 머리 위에 각자의 최고 기록을 띄우고, 발판에 모인 팀을 게임 서버로 보낸다.
--   발판에 올라선 1~Config.Lobby.teamSize명이 한 팀. 처음 올라서면 waitSeconds 뒤, 꽉 차면 fullSeconds 뒤 출발.
--   출발하면 그 팀만 쓰는 새 게임 서버(예약 서버)로 순간이동한다(Config.Places.game). "혼자 바로 시작"은 혼자 바로 출발.
-- Studio에서는 순간이동이 안 돼서, 출발할 때 알림만 띄우고 발판을 다시 비운다(로블록스에 올린 뒤 시험).
-- 최고 기록(며칠까지 버텼는지와 그 판의 총 매출)은 게임과 같은 DataStore(Records)에서 읽는다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage.Shared.Config)
local Plaza = require(script.Parent.Plaza)
local Records = require(script.Parent.Records)

local TICK_SECONDS = 0.2
local LEAVE_TIMEOUT = 20 -- 순간이동을 시작하고 이만큼 지나도 남아 있으면(실패) 다시 발판에 설 수 있다

local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local soloEvent = Instance.new("RemoteEvent")
soloEvent.Name = Config.Lobby.remotes.Solo -- 클라이언트 → 서버: 혼자 바로 시작
soloEvent.Parent = remotes
local toastEvent = Instance.new("RemoteEvent")
toastEvent.Name = Config.Lobby.remotes.Toast -- 서버 → 한 명: 짧은 알림
toastEvent.Parent = remotes
remotes.Parent = ReplicatedStorage

local built = Plaza.build()

type Pad = { spec: Plaza.PadSpec, members: { Player }, departAt: number?, launching: boolean }
local pads: { Pad } = {}
for _, spec in built.pads do
	table.insert(pads, { spec = spec, members = {}, departAt = nil, launching = false })
end
local leaving: { [Player]: number } = {} -- 순간이동 중인 사람(시작한 때)
local warnedFull: { [Player]: boolean } = {}

local RING_EMPTY = Color3.fromRGB(255, 255, 255)
local RING_WAITING = Color3.fromRGB(150, 220, 170)
local RING_FULL = Color3.fromRGB(240, 150, 120)
local RING_LAUNCH = Color3.fromRGB(250, 200, 110)

local function toast(player: Player, text: string)
	toastEvent:FireClient(player, text)
end

local function canTeleport(): boolean
	return Config.Places.game ~= 0 and not RunService:IsStudio()
end

-- 팀을 새 게임 서버로 보낸다. 보내기 시작했으면 true
local function send(team: { Player }): boolean
	if not canTeleport() then
		local why = if RunService:IsStudio()
			then "Studio에서는 순간이동이 안 돼요. 게임을 로블록스에 올린 뒤 시험해요"
			else "게임 장소 id가 아직 없어요 (Config.Places.game)"
		for _, player in team do
			toast(player, why)
		end
		return false
	end
	local started = os.clock()
	for _, player in team do
		leaving[player] = started
		toast(player, "가게로 출발! 🍦")
	end
	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true -- 이 팀만 쓰는 새 게임 서버
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Config.Places.game, team, options)
	end)
	if not ok then
		warn(`게임으로 순간이동 실패: {err}`)
		for _, player in team do
			leaving[player] = nil
			toast(player, "가게로 가지 못했어요. 다시 해 봐요")
		end
	end
	return ok
end

TeleportService.TeleportInitFailed:Connect(function(player: Player, _result: Enum.TeleportResult, message: string)
	leaving[player] = nil
	toast(player, `가게로 가지 못했어요: {message}`)
end)

-- ── 머리 위 최고 기록 ──

local function recordText(player: Player): string
	local day = player:GetAttribute("BestDay")
	local sales = player:GetAttribute("BestSales")
	if typeof(day) == "number" and day > 0 then
		return `🏆 DAY {day}까지 · 매출 {if typeof(sales) == "number" then sales else 0}`
	end
	return "🆕 첫 도전"
end

local function attachRecord(player: Player, character: Model)
	local head = character:WaitForChild("Head", 10)
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Record"
	gui.Size = UDim2.fromOffset(240, 38)
	gui.StudsOffset = Vector3.new(0, 3.4, 0)
	gui.MaxDistance = 90
	gui.LightInfluence = 0
	gui.Adornee = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(96, 78, 68)
	label.BackgroundTransparency = 0.15
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = recordText(player)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 19)
	corner.Parent = label
	label.Parent = gui
	gui.Parent = head
	local function update()
		label.Text = recordText(player)
	end
	player:GetAttributeChangedSignal("BestDay"):Connect(update)
	player:GetAttributeChangedSignal("BestSales"):Connect(update)
end

local function joined(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		attachRecord(player, character)
	end)
	if player.Character then
		task.spawn(attachRecord, player, player.Character)
	end
	task.spawn(function()
		local best = Records.load(player.UserId)
		player:SetAttribute("BestDay", best.day)
		player:SetAttribute("BestSales", best.sales)
	end)
end
Players.PlayerAdded:Connect(joined)
for _, player in Players:GetPlayers() do
	task.spawn(joined, player)
end
Players.PlayerRemoving:Connect(function(player: Player)
	leaving[player] = nil
	warnedFull[player] = nil
end)

-- ── 발판 ──

local function standingOn(player: Player, pad: Pad): boolean
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return false
	end
	local center = pad.spec.center
	local offset = root.Position - center
	return Vector2.new(offset.X, offset.Z).Magnitude <= Plaza.PAD_RADIUS and offset.Y < 8
end

local function render(pad: Pad, now: number)
	local spec = pad.spec
	local count = #pad.members
	local size = Config.Lobby.teamSize
	-- 글 대신 숫자: 👥 몇 명/정원, 사람이 있으면 분홍 배지에 남은 초
	if pad.launching then
		spec.label.Text = "출발!"
		spec.timer.Text = "🍦"
		spec.timer.Visible = true
		spec.ring.Color = RING_LAUNCH
	elseif count == 0 then
		spec.label.Text = `👥 0/{size}`
		spec.timer.Visible = false
		spec.ring.Color = RING_EMPTY
	else
		local left = math.max(0, math.ceil((pad.departAt or now) - now))
		spec.label.Text = `👥 {count}/{size}`
		spec.timer.Text = tostring(left)
		spec.timer.Visible = true
		spec.ring.Color = if count >= size then RING_FULL else RING_WAITING
	end
end

local function launch(pad: Pad)
	pad.launching = true
	local team = table.clone(pad.members)
	task.spawn(function()
		local ok = send(team)
		task.wait(if ok then 8 else 3)
		pad.members = {}
		pad.departAt = nil
		pad.launching = false
	end)
end

local function tickPads()
	local now = os.clock()
	for player, started in leaving do
		if now - started > LEAVE_TIMEOUT or not player.Parent then
			leaving[player] = nil
		end
	end
	local size = Config.Lobby.teamSize
	local onAnyFullPad: { [Player]: boolean } = {}
	for _, pad in pads do
		if not pad.launching then
			-- 먼저 올라선 사람부터 자리를 지킨다
			local members = {}
			for _, member in pad.members do
				if member.Parent and not leaving[member] and standingOn(member, pad) then
					table.insert(members, member)
				end
			end
			for _, player in Players:GetPlayers() do
				if not table.find(members, player) and not leaving[player] and standingOn(player, pad) then
					if #members < size then
						table.insert(members, player)
					else
						onAnyFullPad[player] = true
						if not warnedFull[player] then
							warnedFull[player] = true
							toast(player, "이 발판은 꽉 찼어요. 다른 가게 발판에 올라가요")
						end
					end
				end
			end
			pad.members = members
			if #members == 0 then
				pad.departAt = nil
			else
				pad.departAt = pad.departAt or now + Config.Lobby.waitSeconds
				if #members >= size then
					pad.departAt = math.min(pad.departAt :: number, now + Config.Lobby.fullSeconds)
				end
				if now >= (pad.departAt :: number) then
					launch(pad)
				end
			end
		end
		render(pad, now)
	end
	for player in warnedFull do
		if not onAnyFullPad[player] then
			warnedFull[player] = nil
		end
	end
end

-- 혼자 바로 시작: 서 있던 발판에서 빼고 바로 보낸다
soloEvent.OnServerEvent:Connect(function(player: Player)
	if leaving[player] then
		return
	end
	for _, pad in pads do
		local index = table.find(pad.members, player)
		if index and not pad.launching then
			table.remove(pad.members, index)
		end
	end
	send({ player })
end)

local pending = 0
RunService.Heartbeat:Connect(function(dt: number)
	pending += dt
	if pending >= TICK_SECONDS then
		pending = 0
		tickPads()
	end
end)
