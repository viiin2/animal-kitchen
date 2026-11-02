--!strict
-- 바깥(도시)의 시간 흐름. 영업하는 동안 맑은 아침 → 한낮 → 오후 → 노을 → 해 질 녘으로 바깥 빛이 바뀌고, 밤(정산 화면)에는 어두워진다.
-- 가게 안은 조명으로 늘 같아야 해서 전체 조명(Lighting)은 건드리지 않는다(지붕이 없어 해·하늘빛을 바꾸면 가게 안도 바뀐다).
-- 대신 도시 파트(workspace.Store.City)의 색에 그 시간의 빛을 곱한다. 이 화면에서만 바꾸므로 서버·다른 사람에게는 영향이 없다.
-- 해 질 녘부터 가로등 전구(속성 StreetLamp)와 창문 일부(속성 LitAtNight)에 불이 들어온다(City가 표시해 둔다).
-- 하늘은 바꾸지 못해서 늘 낮 하늘이다(카메라가 내려다봐서 거의 보이지 않는다).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stateEvent = remotes:WaitForChild(Config.Remotes.State) :: RemoteEvent
local readyEvent = remotes:WaitForChild(Config.Remotes.Ready) :: RemoteEvent

-- 하루 진행(0 영업 시작 ~ 1 영업 끝)에 따른 바깥 빛. 파트 색에 곱한다(255가 그대로).
type Key = { at: number, light: Color3 }
local KEYS: { Key } = {
	{ at = 0, light = Color3.fromRGB(222, 232, 250) }, -- 맑은 아침: 살짝 푸르고 조금 어둡게
	{ at = 0.35, light = Color3.fromRGB(255, 255, 255) }, -- 한낮
	{ at = 0.65, light = Color3.fromRGB(255, 246, 232) }, -- 오후
	{ at = 0.85, light = Color3.fromRGB(250, 196, 164) }, -- 노을
	{ at = 1, light = Color3.fromRGB(170, 154, 204) }, -- 해 질 녘
}
local NIGHT = Color3.fromRGB(104, 112, 164) -- 밤(정산 화면)
local LIGHTS_ON = 0.85 -- 하루 진행이 이만큼 지나면 가로등·창문 불을 켠다
local WINDOW_LIT = Color3.fromRGB(255, 232, 196)
local TICK_SECONDS = 0.25

local city = workspace:WaitForChild("Store"):WaitForChild("City")

type Tinted = { part: BasePart, base: Color3 }
local tinted: { Tinted } = {}
local windows: { Tinted } = {}
local bulbs: { BasePart } = {}
for _, object in city:GetDescendants() do
	if object:IsA("BasePart") then
		if object:GetAttribute("StreetLamp") then
			table.insert(bulbs, object)
		elseif object.Material ~= Enum.Material.Neon then -- 신호등·자동차 불은 늘 빛난다
			local item = { part = object, base = object.Color }
			table.insert(tinted, item)
			if object:GetAttribute("LitAtNight") then
				table.insert(windows, item)
			end
		end
	end
end

local phase = "morning"
local endsAt = 0
local daySeconds = 1

-- 지금 하루 진행(0~1). 밤이면 nil
local function progress(): number?
	if phase == "night" then
		return nil
	elseif phase == "open" then
		return math.clamp(1 - (endsAt - workspace:GetServerTimeNow()) / math.max(daySeconds, 1), 0, 1)
	elseif phase == "tutorial" then
		return KEYS[2].at
	end
	return 0 -- 아침·카운트다운
end

local function lightAt(p: number?): Color3
	if not p then
		return NIGHT
	end
	for i = 2, #KEYS do
		local a, b = KEYS[i - 1], KEYS[i]
		if p <= b.at then
			return a.light:Lerp(b.light, (p - a.at) / (b.at - a.at))
		end
	end
	return KEYS[#KEYS].light
end

local shownLight: Color3? = nil
local shownLit: boolean? = nil

local function apply()
	local p = progress()
	local light = lightAt(p)
	local lit = p == nil or p >= LIGHTS_ON
	-- 빛이 눈에 띄게 바뀌었을 때만 다시 칠한다
	local last = shownLight
	local changed = not last
		or math.abs(last.R - light.R) + math.abs(last.G - light.G) + math.abs(last.B - light.B) > 0.006
	if changed then
		shownLight = light
		for _, item in tinted do
			local base = item.base
			item.part.Color = Color3.new(base.R * light.R, base.G * light.G, base.B * light.B)
		end
	end
	if changed or lit ~= shownLit then
		shownLit = lit
		for _, window in windows do
			local part, base = window.part, window.base
			if lit then
				part.Material = Enum.Material.Neon
				part.Color = WINDOW_LIT
			else
				part.Material = Enum.Material.SmoothPlastic
				part.Color = Color3.new(base.R * light.R, base.G * light.G, base.B * light.B)
			end
		end
		for _, bulb in bulbs do
			bulb.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
			local lamp = bulb:FindFirstChildOfClass("PointLight")
			if lamp then
				lamp.Enabled = lit
			end
		end
	end
end

stateEvent.OnClientEvent:Connect(function(state: { phase: string, endsAt: number, daySeconds: number })
	phase = state.phase
	endsAt = state.endsAt
	daySeconds = state.daySeconds
	apply()
end)

local pending = 0
RunService.Heartbeat:Connect(function(dt: number)
	pending += dt
	if pending >= TICK_SECONDS then
		pending = 0
		apply()
	end
end)

apply()
-- 다른 화면 스크립트보다 늦게 연결됐어도 지금 상태를 받는다
readyEvent:FireServer()
