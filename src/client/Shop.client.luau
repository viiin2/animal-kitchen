--!strict
-- 상점 창: 아침·밤 창의 "상점"(LocalPlayer 속성 ShopOpen = true)으로 연다.
-- 위에는 빚(남은 빚, 밤마다 붙는 이자, 갚을 금액을 −/+로 골라 갚기), 아래에는 스킬·기구 카드(그림·단계·설명·값).
-- 사고 갚는 것은 서버(Days.buy, Days.payDebt)가 판정하고, 코인은 모두가 같이 쓴다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UiDeco = require(ReplicatedStorage.Shared.UiDeco)
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local stateEvent = remotes:WaitForChild(Config.Remotes.State) :: RemoteEvent
local readyEvent = remotes:WaitForChild(Config.Remotes.Ready) :: RemoteEvent
local buyEvent = remotes:WaitForChild(Config.Remotes.Buy) :: RemoteEvent
local payEvent = remotes:WaitForChild(Config.Remotes.PayDebt) :: RemoteEvent

type ShopView = { id: string, name: string, desc: string, level: number, max: number, cost: number? }
type Card = { level: TextLabel, buy: TextButton }

local BODY = Enum.Font.GothamBold
local ROUND = Enum.Font.FredokaOne
local INK = Color3.fromRGB(110, 76, 90)
local MUTED = Color3.fromRGB(168, 136, 150)
local PAPER = Color3.fromRGB(255, 248, 251)
local CARD = Color3.fromRGB(255, 238, 245)
local PINK = Color3.fromRGB(250, 196, 212)
local CORAL = Color3.fromRGB(236, 132, 100)
local SAGE = Color3.fromRGB(134, 178, 126)
local GOLD = Color3.fromRGB(196, 140, 48)
local GRAY = Color3.fromRGB(214, 204, 210)
local WHITE = Color3.new(1, 1, 1)

local WIDTH, HEIGHT = 720, 600

local player = Players.LocalPlayer
local shop: { ShopView } = {}
local wallet = 0
local debt = 0
local payAmount = 50 -- 갚을 금액(−/+ 10씩)
local PAY_STEP = 10
local phase = "morning"

local gui = Instance.new("ScreenGui")
gui.Name = "ShopWindow"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 8
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function text(parent: Instance, value: string, size: number, color: Color3, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font or BODY
	l.TextSize = size
	l.TextColor3 = color
	l.Text = value
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function button(parent: Instance, value: string, size: UDim2, color: Color3, textColor: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = BODY
	b.TextSize = 14
	b.TextColor3 = textColor
	b.Text = value
	corner(b, 12)
	b.Parent = parent
	return b
end

-- ── 창 ──

local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.fromRGB(60, 40, 50)
dim.BackgroundTransparency = 0.55
dim.BorderSizePixel = 0
dim.Parent = gui

local window = Instance.new("Frame")
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromOffset(WIDTH, HEIGHT)
window.BackgroundColor3 = PAPER
window.BorderSizePixel = 0
corner(window, 22)
stroke(window, PINK, 3)
window.Parent = gui
UiDeco.header(window, 44, 22)
local scale = Instance.new("UIScale")
scale.Parent = window

local title = text(window, "상점", 26, CORAL, ROUND)
title.Position = UDim2.fromOffset(24, 14)
title.Size = UDim2.fromOffset(200, 34)
local coinLabel = text(window, "", 18, GOLD, ROUND)
coinLabel.AnchorPoint = Vector2.new(1, 0)
coinLabel.Position = UDim2.new(1, -24, 0, 16)
coinLabel.Size = UDim2.fromOffset(240, 30)
coinLabel.TextXAlignment = Enum.TextXAlignment.Right

-- 빚
local debtCard = Instance.new("Frame")
debtCard.Position = UDim2.fromOffset(24, 56)
debtCard.Size = UDim2.new(1, -48, 0, 78)
debtCard.BackgroundColor3 = Color3.fromRGB(255, 244, 228)
debtCard.BorderSizePixel = 0
corner(debtCard, 16)
debtCard.Parent = window
local debtTitle = text(debtCard, "", 20, INK, ROUND)
debtTitle.Position = UDim2.fromOffset(16, 10)
debtTitle.Size = UDim2.fromOffset(320, 28)
local debtNote = text(debtCard, "", 12, MUTED)
debtNote.Position = UDim2.fromOffset(16, 40)
debtNote.Size = UDim2.fromOffset(300, 30)
debtNote.TextWrapped = true
debtNote.TextYAlignment = Enum.TextYAlignment.Top
local payRow = Instance.new("Frame")
payRow.BackgroundTransparency = 1
payRow.AnchorPoint = Vector2.new(1, 0.5)
payRow.Position = UDim2.new(1, -14, 0.5, 0)
payRow.Size = UDim2.fromOffset(330, 36)
payRow.Parent = debtCard
local payLayout = Instance.new("UIListLayout")
payLayout.FillDirection = Enum.FillDirection.Horizontal
payLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
payLayout.Padding = UDim.new(0, 8)
payLayout.SortOrder = Enum.SortOrder.LayoutOrder
payLayout.Parent = payRow
-- [−] 금액 [+] [갚기] [전부 갚기]
local minus = button(payRow, "−", UDim2.fromOffset(36, 36), WHITE, INK)
minus.LayoutOrder = 1
minus.TextSize = 20
stroke(minus, PINK, 2)
local amountLabel = text(payRow, "", 18, INK, ROUND)
amountLabel.LayoutOrder = 2
amountLabel.Size = UDim2.fromOffset(64, 36)
amountLabel.TextXAlignment = Enum.TextXAlignment.Center
local plus = button(payRow, "+", UDim2.fromOffset(36, 36), WHITE, INK)
plus.LayoutOrder = 3
plus.TextSize = 20
stroke(plus, PINK, 2)
local payButton = button(payRow, "갚기", UDim2.fromOffset(70, 36), CORAL, WHITE)
payButton.LayoutOrder = 4
local payAll = button(payRow, "전부 갚기", UDim2.fromOffset(88, 36), CORAL, WHITE)
payAll.LayoutOrder = 5
local payButtons: { TextButton } = { payButton, payAll }

-- 스킬·기구 카드
local grid = Instance.new("Frame")
grid.BackgroundTransparency = 1
grid.Position = UDim2.fromOffset(24, 148)
grid.Size = UDim2.new(1, -48, 1, -210)
grid.Parent = window
local layout = Instance.new("UIGridLayout")
layout.CellSize = UDim2.fromOffset(216, 118)
layout.CellPadding = UDim2.fromOffset(10, 10)
layout.FillDirectionMaxCells = 3
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = grid

local close = button(window, "닫기", UDim2.fromOffset(120, 42), WHITE, INK)
close.AnchorPoint = Vector2.new(1, 1)
close.Position = UDim2.new(1, -24, 1, -14)
close.TextSize = 16
stroke(close, PINK, 2)
local hint = text(window, "스킬과 기구는 모두에게 적용되고, 코인은 모두가 같이 써요.", 12, MUTED)
hint.AnchorPoint = Vector2.new(0, 1)
hint.Position = UDim2.new(0, 24, 1, -24)
hint.Size = UDim2.fromOffset(420, 20)

local cards: { [string]: Card } = {}

for i, upgrade in Config.Upgrades do
	local card = Instance.new("Frame")
	card.BackgroundColor3 = CARD
	card.BorderSizePixel = 0
	card.LayoutOrder = i
	corner(card, 16)
	card.Parent = grid

	local icon = Instance.new("TextLabel")
	icon.BackgroundColor3 = WHITE
	icon.Position = UDim2.fromOffset(10, 10)
	icon.Size = UDim2.fromOffset(46, 46)
	icon.Font = BODY
	icon.TextSize = 28
	icon.Text = upgrade.icon
	corner(icon, 23)
	icon.Parent = card

	local name = text(card, upgrade.name, 14, INK)
	name.Position = UDim2.fromOffset(64, 10)
	name.Size = UDim2.new(1, -72, 0, 20)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local level = text(card, "", 13, GOLD)
	level.Position = UDim2.fromOffset(64, 32)
	level.Size = UDim2.new(1, -72, 0, 18)
	local desc = text(card, upgrade.desc, 12, MUTED)
	desc.Position = UDim2.fromOffset(10, 62)
	desc.Size = UDim2.new(1, -120, 0, 44)
	desc.TextWrapped = true
	desc.TextYAlignment = Enum.TextYAlignment.Top

	local buy = button(card, "", UDim2.fromOffset(92, 34), SAGE, WHITE)
	buy.AnchorPoint = Vector2.new(1, 1)
	buy.Position = UDim2.new(1, -10, 1, -10)
	buy.Activated:Connect(function()
		buyEvent:FireServer(upgrade.id)
	end)
	cards[upgrade.id] = { level = level, buy = buy }
end

-- 갚을 수 있는 만큼(빚과 코인 중 작은 쪽) 안에서 금액을 맞춘다
local function maxPay(): number
	return math.max(0, math.min(debt, wallet))
end

local function clampPay()
	local most = maxPay()
	payAmount = if most <= 0 then 0 else math.clamp(payAmount, math.min(PAY_STEP, most), most)
end

local function render()
	coinLabel.Text = `코인 {wallet}`
	clampPay()
	amountLabel.Text = tostring(payAmount)
	if debt > 0 then
		debtTitle.Text = `남은 빚 {debt}`
		debtNote.Text = `밤마다 남은 빚의 {math.floor(Config.Debt.interest * 100 + 0.5)}% 이자가 붙어요. 얼마나 갚을지 골라요(일찍 갚을수록 이자가 줄어요).`
	else
		debtTitle.Text = "빚을 다 갚았어요!"
		debtNote.Text = "이제 번 코인은 모두 가게를 키우는 데 써요."
	end
	payRow.Visible = debt > 0
	for _, b in payButtons do
		b.BackgroundColor3 = if maxPay() > 0 then CORAL else GRAY
	end
	for _, item in shop do
		local card = cards[item.id]
		if card then
			card.level.Text = `{string.rep("●", item.level)}{string.rep("○", item.max - item.level)}`
			local cost = item.cost
			local affordable = cost ~= nil and wallet >= cost
			card.buy.Text = if cost then `{cost} 코인` else "최고 단계"
			card.buy.BackgroundColor3 = if affordable then SAGE else GRAY
			card.buy.TextColor3 = if affordable then WHITE else INK
			card.buy.AutoButtonColor = affordable
		end
	end
end

local function applyScale()
	local camera = workspace.CurrentCamera
	if camera then
		local size = camera.ViewportSize
		scale.Scale = math.clamp(math.min((size.X - 24) / WIDTH, (size.Y - 40) / HEIGHT), 0.4, 1)
	end
end

local function setOpen(open: boolean)
	gui.Enabled = open
	if open then
		applyScale()
		render()
	elseif player:GetAttribute("ShopOpen") == true then
		player:SetAttribute("ShopOpen", false)
	end
end

close.Activated:Connect(function()
	setOpen(false)
end)
player:GetAttributeChangedSignal("ShopOpen"):Connect(function()
	setOpen(player:GetAttribute("ShopOpen") == true)
end)

minus.Activated:Connect(function()
	payAmount -= PAY_STEP
	render()
end)
plus.Activated:Connect(function()
	payAmount += PAY_STEP
	render()
end)
payButton.Activated:Connect(function()
	if payAmount > 0 then
		payEvent:FireServer(payAmount)
	end
end)
payAll.Activated:Connect(function()
	payEvent:FireServer("all")
end)

stateEvent.OnClientEvent:Connect(function(incoming: { phase: string, wallet: number, shop: { ShopView }?, debt: number? })
	phase = incoming.phase
	wallet = incoming.wallet
	shop = incoming.shop or {}
	debt = incoming.debt or 0
	-- 영업이 시작되면 창을 닫는다
	if phase ~= "morning" and phase ~= "night" and gui.Enabled then
		setOpen(false)
	elseif gui.Enabled then
		render()
	end
end)

-- Hud보다 늦게 연결됐어도 지금 상태(코인·상점 단계·빚)를 받는다
readyEvent:FireServer()
