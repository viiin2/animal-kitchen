--!strict
-- 카페에서 옮기는 물건: 재료, 디저트·음료, 아이스크림, 쟁반, 소화기. 모양은 FoodModels가 만든다.
-- 이름표는 월드에 띄우지 않는다(화면을 가린다). 이름은 손에 든 것(HUD)과 가까이 갔을 때의 프롬프트에만 보인다.
-- 물건은 늘 한 곳에만 있다: 손(held), 스테이션 위(at), 쟁반 위(plate). 위치는 이 모듈의 함수로만 바꾼다.
-- 모델 안의 파트는 Root에 용접돼 있고(Build.rig), 옮길 때는 Root를 고정한 채 PivotTo로 통째로 옮긴다.
-- 아이스크림은 만든 순간부터 녹는다(meltFrom~meltTo). 흘러내리기 시작하면 melt 1, 다 녹으면 2이고 낼 수 없다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Build = require(ReplicatedStorage.Shared.Build)
local FoodModels = require(ReplicatedStorage.Shared.FoodModels)

export type Place = { kind: "none" } | { kind: "held", root: BasePart } | { kind: "at", surface: CFrame } | { kind: "plate" }

export type Item = {
	kind: string, -- 재료 키 | 요리 키 | icecream | plate(쟁반) | extinguisher
	state: string, -- 재료 raw, 요리 prepped | cooked | sauced | burnt
	spec: Config.IceSpec?, -- 아이스크림: 그릇·맛·토핑
	melt: number, -- 0 그대로, 1 흘러내림, 2 다 녹음
	meltFrom: number?,
	meltTo: number?,
	contents: Item?, -- 쟁반 위 디저트
	tray: Item?, -- 이 디저트가 올라간 쟁반
	model: Model,
	root: BasePart,
	joints: { WeldConstraint }, -- 바깥과 잇는 용접(손, 쟁반)
	place: Place,
}

export type Options = { spec: Config.IceSpec?, meltSeconds: number? }

local HOLD_OFFSET = CFrame.new(0, 0.5, -2.1) -- 캐릭터 앞, 가슴 높이
local MELT_WARNING = 0.6 -- 녹는 시간의 60%가 지나면 흘러내린다

local Items = {}

local folder: Instance? = nil
local melting: { [Item]: boolean } = {}

function Items.init(parent: Instance)
	folder = parent
end

local function now(): number
	return workspace:GetServerTimeNow()
end

function Items.isIngredient(item: Item): boolean
	return Config.Ingredients[item.kind] ~= nil
end

function Items.isDish(item: Item): boolean
	return Config.Dishes[item.kind] ~= nil
end

function Items.labelText(item: Item): string
	local ingredient = Config.Ingredients[item.kind]
	if ingredient then
		return ingredient.name
	end
	local spec = item.spec
	if item.kind == "icecream" and spec then
		local name = Config.iceName(spec)
		return if item.melt >= 2 then `녹아 버린 {name}` elseif item.melt == 1 then `{name} (녹는 중!)` else name
	end
	local dish = Config.Dishes[item.kind]
	if dish then
		local state = item.state
		local cooker = dish.cooker
		if state == "burnt" then
			return "탄 " .. dish.name
		elseif state == "prepped" and cooker then
			return `{dish.name} ({Config.Cookers[cooker].verb} 전)`
		elseif state == "cooked" and dish.sauce then
			return `{dish.name} (토핑 전)`
		end
		return dish.name
	end
	if item.kind == "plate" then
		local contents = item.contents
		return if contents then Items.labelText(contents) else "빈 쟁반"
	elseif item.kind == "dishes" then
		return "빈 그릇"
	end
	return "소화기"
end

local function build(item: { kind: string, state: string, melt: number, spec: Config.IceSpec? }): (Model, BasePart)
	local model = FoodModels.build(item.kind, item.state, item.melt, item.spec)
	local root = Build.rig(model)
	model.Parent = folder
	return model, root
end

local function clearJoints(item: Item)
	for _, joint in item.joints do
		joint:Destroy()
	end
	table.clear(item.joints)
end

local function weld(item: Item, a: BasePart, b: BasePart)
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = a
	joint.Part1 = b
	joint.Parent = b
	table.insert(item.joints, joint)
end

-- place에 맞게 다시 놓는다. 쟁반이면 위의 디저트도 함께 옮긴다.
-- 고정한 채로 자리를 잡은 뒤 용접하고, 손에 든 것만 고정을 푼다.
local function apply(item: Item)
	local place = item.place
	local surface: CFrame
	if place.kind == "held" then
		surface = place.root.CFrame * HOLD_OFFSET
	elseif place.kind == "at" then
		surface = place.surface
	else
		return
	end

	clearJoints(item)
	local contents = item.contents
	if contents then
		clearJoints(contents)
	end
	item.root.Anchored = true
	item.model:PivotTo(surface * CFrame.new(0, item.root.Size.Y / 2, 0))
	if contents then
		contents.root.Anchored = true
		contents.model:PivotTo(item.root.CFrame * CFrame.new(0, item.root.Size.Y / 2 + contents.root.Size.Y / 2, 0))
	end

	if place.kind == "held" then
		if contents then
			weld(item, item.root, contents.root)
			contents.root.Massless = true
			contents.root.Anchored = false
		end
		weld(item, place.root, item.root)
		item.root.Massless = true
		item.root.Anchored = false
	end
end

-- 모양을 새로 만들어 같은 자리에 둔다(쟁반 위면 쟁반째 다시 놓는다)
local function rebuild(item: Item)
	clearJoints(item)
	local old = item.model
	item.model, item.root = build(item)
	old:Destroy()
	local tray = item.tray
	if tray then
		apply(tray)
	else
		apply(item)
	end
end

function Items.new(kind: string, state: string, options: Options?): Item
	local spec = options and options.spec
	local meltSeconds = options and options.meltSeconds
	local model, root = build({ kind = kind, state = state, melt = 0, spec = spec })
	local item: Item = {
		kind = kind,
		state = state,
		spec = spec,
		melt = 0,
		meltFrom = nil,
		meltTo = nil,
		contents = nil,
		tray = nil,
		model = model,
		root = root,
		joints = {},
		place = { kind = "none" },
	}
	if meltSeconds then
		local t = now()
		item.meltFrom = t
		item.meltTo = t + meltSeconds
		melting[item] = true
	end
	return item
end

function Items.hold(item: Item, root: BasePart)
	item.place = { kind = "held", root = root }
	apply(item)
end

function Items.putAt(item: Item, surface: CFrame)
	item.place = { kind = "at", surface = surface }
	apply(item)
end

function Items.setState(item: Item, state: string)
	item.state = state
	rebuild(item)
end

-- 녹는 단계가 바뀐 물건을 다시 그린다. 단계가 바뀐 물건 목록을 돌려준다(손에 든 이름 갱신용).
function Items.tickMelt(): { Item }
	local t = now()
	local changed = {}
	for item in melting do
		local from, to = item.meltFrom, item.meltTo
		if from and to then
			local stage = if t >= to then 2 elseif t >= from + (to - from) * MELT_WARNING then 1 else 0
			if stage ~= item.melt then
				item.melt = stage
				rebuild(item)
				table.insert(changed, item)
				if stage >= 2 then
					melting[item] = nil
				end
			end
		end
	end
	return changed
end

-- 손님에게 낼 수 있는 상태(익음·토핑)만 빈 쟁반에 담는다. 담았으면 true.
function Items.addToPlate(plate: Item, food: Item): boolean
	if plate.kind ~= "plate" or plate.contents ~= nil or not Items.isDish(food) then
		return false
	end
	if food.state ~= "cooked" and food.state ~= "sauced" then
		return false
	end
	clearJoints(food)
	food.place = { kind = "plate" }
	food.tray = plate
	plate.contents = food
	apply(plate)
	return true
end

function Items.destroy(item: Item)
	local contents = item.contents
	if contents then
		Items.destroy(contents)
	end
	melting[item] = nil
	clearJoints(item)
	item.model:Destroy()
end

function Items.clearPlate(plate: Item)
	local contents = plate.contents
	if contents then
		plate.contents = nil
		Items.destroy(contents)
		apply(plate)
	end
end

return Items
