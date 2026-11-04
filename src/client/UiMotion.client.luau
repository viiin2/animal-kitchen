--!strict
-- 모든 화면 버튼의 말랑한 손맛: 마우스를 올리면 살짝 커지고, 누르면 꾹 눌렸다가 통 튀어 돌아온다.
-- 버튼마다 UIScale "Bounce"를 하나 단다. 이미 UIScale이 있는 버튼(다른 효과가 쓰는 중)은 건드리지 않는다.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local HOVER = 1.06
local PRESS = 0.9

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local hooked: { [GuiButton]: boolean } = {}

local function to(scale: UIScale, value: number, seconds: number, style: Enum.EasingStyle)
	TweenService:Create(scale, TweenInfo.new(seconds, style, Enum.EasingDirection.Out), { Scale = value }):Play()
end

local function hook(object: Instance)
	if not object:IsA("GuiButton") or hooked[object] or object:FindFirstChildOfClass("UIScale") then
		return
	end
	hooked[object] = true
	local scale = Instance.new("UIScale")
	scale.Name = "Bounce"
	scale.Parent = object
	local hovering = false
	object.MouseEnter:Connect(function()
		hovering = true
		to(scale, HOVER, 0.15, Enum.EasingStyle.Quad)
	end)
	object.MouseLeave:Connect(function()
		hovering = false
		to(scale, 1, 0.15, Enum.EasingStyle.Quad)
	end)
	object.MouseButton1Down:Connect(function()
		to(scale, PRESS, 0.08, Enum.EasingStyle.Quad)
	end)
	object.MouseButton1Up:Connect(function()
		to(scale, if hovering then HOVER else 1, 0.3, Enum.EasingStyle.Back)
	end)
	-- 터치·게임패드: 누를 때마다 한 번 꾹-통
	object.Activated:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			scale.Scale = PRESS
			to(scale, 1, 0.3, Enum.EasingStyle.Back)
		end
	end)
	object.Destroying:Connect(function()
		hooked[object] = nil
	end)
end

playerGui.DescendantAdded:Connect(function(object: Instance)
	-- 만든 직후 UIScale을 붙이는 코드가 먼저 돌도록 한 박자 늦게
	task.defer(hook, object)
end)
for _, object in playerGui:GetDescendants() do
	hook(object)
end
