--!strict
-- 서버 시작점: 카페를 짓고, 스테이션·홀 테이블·손님·하루 진행을 잇고, 플레이어마다 동물 캐릭터를 직접 만들어 준다.
-- 로블록스 아바타는 쓰지 않는다(CharacterAutoLoads 끔, default.project.json). 캐릭터는 Avatars가 만든다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local AnimalLooks = require(ReplicatedStorage.Shared.AnimalLooks)

local Store = require(script.Parent.Store)
local Stations = require(script.Parent.Stations)
local Tables = require(script.Parent.Tables)
local Customers = require(script.Parent.Customers)
local Days = require(script.Parent.Days)
local Avatars = require(script.Parent.Avatars)
local Remotes = require(script.Parent.Remotes)
require(script.Parent.QuickChat)

local Config = require(ReplicatedStorage.Shared.Config)

local RESPAWN_SECONDS = 3
local UNSTUCK_COOLDOWN = 3

Players.CharacterAutoLoads = false

local layout = Store.build()
Stations.init(layout)
Tables.init(layout)
Customers.init(layout)
Days.init(layout)
Avatars.setSpawn(layout.spawn)

-- 팀 콤보: 다른 친구가 Config.Combo.seconds 안에 이어서 내면 콤보가 오른다(혼자 연달아 내면 유지)
local lastServer: Player? = nil
local lastServeAt = -math.huge
local combo = 0

-- 손님 자리에 디저트를 내면: 손님이 주문한 디저트인지 보고, 맞으면 그날 매출(코인)에 더한다
Stations.onServe = function(player: Player, seat: number, dish): (boolean, string)
	local tipBonus = AnimalLooks.perksFor(player:GetAttribute("AnimalIndex")).tip
	local ok, message, price, tip = Customers.serveAt(seat, { kind = dish.kind, state = dish.state, melt = dish.melt, spec = dish.spec }, tipBonus)
	if ok then
		local t = os.clock()
		if t - lastServeAt > Config.Combo.seconds then
			combo = 0
		elseif lastServer ~= player then
			combo += 1
		end
		lastServer, lastServeAt = player, t
		local bonus = if price > 0 then combo * Config.Combo.bonus else 0
		if bonus > 0 then
			message = `{message} · 팀 콤보 x{combo + 1} +{bonus}`
		end
		Days.earn(price, tip + bonus)
		Days.stat(player, "served", 1)
		Days.stat(player, "coins", price + tip + bonus)
		local stand = layout.seats[seat]
		if stand and price > 0 then
			Remotes.Earned:FireAllClients(stand.stand.Position + Vector3.new(0, 7.5, 0), price + tip + bonus, combo)
		end
		-- 튜토리얼이 "손님에게 냈다"를 이 숫자로 안다
		local served = player:GetAttribute("Served")
		player:SetAttribute("Served", (if typeof(served) == "number" then served else 0) + 1)
	end
	return ok, message
end
Customers.onMissed = Days.missed

Avatars.onSpawn = function(player: Player, humanoid: Humanoid)
	humanoid.WalkSpeed = Days.walkSpeed(player)
	humanoid.Died:Connect(function()
		Stations.drop(player)
		task.delay(RESPAWN_SECONDS, function()
			if player.Parent and player.Character == humanoid.Parent then
				Avatars.spawn(player)
			end
		end)
	end)
end

-- 관리자: Studio에서는 모두, 실제 서버에서는 게임 주인과 Config.Admins
local function isAdmin(player: Player): boolean
	if RunService:IsStudio() or table.find(Config.Admins, player.UserId) then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId
end

local function joined(player: Player)
	player:SetAttribute("Admin", isAdmin(player)) -- 화면에 관리자 버튼을 보일지(판정은 아래에서 다시 한다)
	Avatars.spawn(player)
	Avatars.loadPasses(player)
end
Players.PlayerAdded:Connect(joined)
for _, player in Players:GetPlayers() do
	task.spawn(joined, player)
end

Remotes.Admin.OnServerEvent:Connect(function(player: Player, action: unknown)
	if not isAdmin(player) then
		return
	end
	if action == "pass" then
		Days.adminPass()
	elseif action == "stop" then
		Days.adminStop()
	end
end)
Players.PlayerRemoving:Connect(Stations.drop)

Remotes.Ready.OnServerEvent:Connect(Days.sendTo)
-- 아침에는 바로 시작, 밤에는 준비(모두 준비하면 시작)
Remotes.Start.OnServerEvent:Connect(Days.pressStart)
Remotes.Buy.OnServerEvent:Connect(Days.buy)
Remotes.PayDebt.OnServerEvent:Connect(Days.payDebt)
-- 동물 고르기 창: 연 동물이면 바로 바꾼다(잠긴 동물은 게임패스, Avatars)
Remotes.Animal.OnServerEvent:Connect(function(player: Player, index: unknown)
	if typeof(index) ~= "number" or index % 1 ~= 0 or not AnimalLooks.list[index] then
		return
	end
	Avatars.request(player, index)
end)
Avatars.onSwitch = Stations.drop
Tables.onClear = Stations.giveDishes
Stations.onStat = Days.stat
Stations.onSpend = Days.spend
Remotes.Tutorial.OnServerEvent:Connect(function(_player: Player, on: unknown)
	if on == true then
		Days.startTutorial()
	elseif on == false then
		Days.endTutorial(false)
	end
end)
local lastUnstuck: { [Player]: number } = {}
Remotes.Unstuck.OnServerEvent:Connect(function(player: Player)
	local t = os.clock()
	if t - (lastUnstuck[player] or -math.huge) < UNSTUCK_COOLDOWN then
		return
	end
	lastUnstuck[player] = t
	Avatars.teleport(player)
end)
Players.PlayerRemoving:Connect(function(player: Player)
	lastUnstuck[player] = nil
end)
