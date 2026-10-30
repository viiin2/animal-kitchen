--!strict
-- 플레이어 캐릭터: 로블록스 아바타 대신 이 게임의 동물 인형(Critters.character)으로 직접 만들어 준다.
-- 처음 들어오면 공짜 동물 중에서 들어온 순서대로 정하고, 동물 고르기 창(Remotes.Animal)에서 고르면 그 동물로 다시 만든다.
-- 공짜가 아닌 동물은 게임패스(Robux)로 사람마다 연다(AnimalLooks의 robux·pass). 연 동물 목록은 속성 OwnedAnimals("1,2,3").
-- 게임패스 id가 아직 0인 동물은 Studio에서만 시험으로 무료로 열어 준다.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local AnimalLooks = require(ReplicatedStorage.Shared.AnimalLooks)
local Critters = require(script.Parent.Critters)
local Remotes = require(script.Parent.Remotes)

local Avatars = {}

-- 캐릭터가 새로 생길 때(이동 속도 등). Main이 Days.walkSpeed를 넣는다.
Avatars.onSpawn = function(_player: Player, _humanoid: Humanoid) end
-- 다른 동물로 바꾸기 직전(손에 든 것 내려놓기). Main이 Stations.drop을 넣는다.
Avatars.onSwitch = function(_player: Player) end

local choice: { [Player]: number } = {}
local owned: { [Player]: { [number]: boolean } } = {}
local joined = 0
local spawnAt = CFrame.new(0, 2.2, 9.5)

local function freeAnimals(): { number }
	local free = {}
	for i, look in AnimalLooks.list do
		if look.robux <= 0 then
			table.insert(free, i)
		end
	end
	return free
end

function Avatars.owns(player: Player, index: number): boolean
	local look = AnimalLooks.list[index]
	if not look then
		return false
	elseif look.robux <= 0 then
		return true
	end
	local mine = owned[player]
	return mine ~= nil and mine[index] == true
end

local function publishOwned(player: Player)
	local list = {}
	for i in AnimalLooks.list do
		if Avatars.owns(player, i) then
			table.insert(list, tostring(i))
		end
	end
	player:SetAttribute("OwnedAnimals", table.concat(list, ","))
end

local function grant(player: Player, index: number)
	local mine = owned[player] or {}
	mine[index] = true
	owned[player] = mine
	publishOwned(player)
end

function Avatars.setSpawn(cframe: CFrame)
	spawnAt = cframe
end

function Avatars.current(player: Player): number?
	return choice[player]
end

function Avatars.spawn(player: Player, at: CFrame?)
	if not player.Parent then
		return
	end
	local index = choice[player]
	if not index then
		local free = freeAnimals()
		joined += 1
		index = free[(joined - 1) % #free + 1]
		choice[player] = index
	end
	local old = player.Character
	local model = Critters.character(index)
	model.Name = player.Name
	model:PivotTo(at or spawnAt)
	model.Parent = workspace
	player.Character = model
	local root = model.PrimaryPart
	if root then
		root:SetNetworkOwner(player)
	end
	if old and old ~= model then
		old:Destroy()
	end
	player:SetAttribute("Animal", Critters.lookName(index))
	player:SetAttribute("AnimalIndex", index)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		Avatars.onSpawn(player, humanoid)
	end
end

-- 고른 동물로 바꾼다. 서 있던 자리에서 다시 만든다.
function Avatars.choose(player: Player, index: number)
	if choice[player] == index then
		return
	end
	Avatars.onSwitch(player)
	choice[player] = index
	local character = player.Character
	local root = character and character.PrimaryPart
	Avatars.spawn(player, if root then root.CFrame else nil)
end

-- 끼었을 때: 들고 있는 것은 그대로 두고 처음 자리로 옮긴다
function Avatars.teleport(player: Player)
	local character = player.Character
	if character then
		character:PivotTo(spawnAt)
	end
end

-- 동물 고르기 창에서 골랐을 때. 연 동물이면 바꾼다.
function Avatars.request(player: Player, index: number)
	local look = AnimalLooks.list[index]
	if not look then
		return
	end
	if not Avatars.owns(player, index) then
		if look.pass == 0 and RunService:IsStudio() then
			grant(player, index)
			Remotes.toast(player, `Studio 시험: '{look.name}'을(를) 무료로 열었어요 (게임패스 id를 넣으면 Robux 결제로 바뀌어요)`)
		else
			Remotes.toast(player, if look.pass == 0 then "아직 판매 준비 중이에요" else "Robux로 열 수 있어요")
			return
		end
	end
	Avatars.choose(player, index)
end

-- 들어올 때 이미 산 게임패스를 확인한다
function Avatars.loadPasses(player: Player)
	for i, look in AnimalLooks.list do
		if look.pass > 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, look.pass)
			end)
			if ok and has and player.Parent then
				grant(player, i)
			end
		end
	end
	publishOwned(player)
end

-- 동물 고르기 창에서 결제했을 때(결제 창은 클라이언트가 띄운다)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	for i, look in AnimalLooks.list do
		if look.pass == passId then
			grant(player, i)
			Remotes.toast(player, `'{look.name}'을(를) 열었어요!`)
			Remotes.sfx(player, "buy")
			Avatars.choose(player, i)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	choice[player] = nil
	owned[player] = nil
	local character = player.Character
	if character then
		character:Destroy()
	end
end)

return Avatars
