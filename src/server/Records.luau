--!strict
-- 최고 기록(며칠까지 버텼는지)을 플레이어마다 DataStore에 저장한다.
-- DataStore를 못 쓰면(Studio에서 'Studio Access to API Services'를 안 켰을 때 등) 조용히 넘어가고, Days가 이 서버에서만 기억한다.
local DataStoreService = game:GetService("DataStoreService")

local Records = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function(): DataStore
		return DataStoreService:GetDataStore("BestDay")
	end)
	if ok then
		store = result
	end
end

local function key(userId: number): string
	return `u{userId}`
end

-- 저장된 최고 기록(없거나 못 읽으면 0). 기다린다(task.spawn 안에서 부른다).
function Records.load(userId: number): number
	local current = store
	if not current then
		return 0
	end
	local ok, value = pcall(function(): any
		return current:GetAsync(key(userId))
	end)
	return if ok and typeof(value) == "number" then value else 0
end

-- 더 높을 때만 저장한다. 기다린다(task.spawn 안에서 부른다).
function Records.save(userId: number, day: number)
	local current = store
	if not current then
		return
	end
	pcall(function()
		current:UpdateAsync(key(userId), function(old: any): any
			return if typeof(old) == "number" and old >= day then nil else day
		end)
	end)
end

return Records
