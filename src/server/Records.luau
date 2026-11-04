--!strict
-- 최고 기록을 플레이어마다 DataStore에 저장한다: 가장 오래 버틴 판의 날짜(DAY)와 그 판의 총 매출.
-- 날짜가 같으면 매출이 높은 쪽을 남긴다. 같은 체험의 다른 장소(로비)도 이 저장소를 읽어 머리 위에 띄울 수 있다.
-- DataStore를 못 쓰면(Studio에서 'Studio Access to API Services'를 안 켰을 때 등) 조용히 넘어가고, Days가 이 서버에서만 기억한다.
local DataStoreService = game:GetService("DataStoreService")

export type Best = { day: number, sales: number }

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

-- 저장된 값을 기록으로 읽는다(예전에는 날짜 숫자만 저장했다)
local function parse(value: any): Best
	if typeof(value) == "number" then
		return { day = value, sales = 0 }
	elseif typeof(value) == "table" and typeof(value.day) == "number" then
		return { day = value.day, sales = if typeof(value.sales) == "number" then value.sales else 0 }
	end
	return { day = 0, sales = 0 }
end

-- a가 b보다 좋은 기록인지: 더 오래 버텼거나, 같은 날까지 버티고 매출이 더 높다
function Records.better(a: Best, b: Best): boolean
	return a.day > b.day or (a.day == b.day and a.sales > b.sales)
end

-- 저장된 최고 기록(없거나 못 읽으면 0일). 기다린다(task.spawn 안에서 부른다).
function Records.load(userId: number): Best
	local current = store
	if not current then
		return parse(nil)
	end
	local ok, value = pcall(function(): any
		return current:GetAsync(key(userId))
	end)
	return parse(if ok then value else nil)
end

-- 더 좋을 때만 저장한다. 기다린다(task.spawn 안에서 부른다).
function Records.save(userId: number, best: Best)
	local current = store
	if not current then
		return
	end
	pcall(function()
		current:UpdateAsync(key(userId), function(old: any): any
			return if Records.better(best, parse(old)) then { day = best.day, sales = best.sales } else nil
		end)
	end)
end

return Records
