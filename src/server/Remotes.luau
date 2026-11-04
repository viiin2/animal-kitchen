--!strict
-- 서버↔클라이언트 RemoteEvent. 이름은 Config.Remotes. 서버가 시작할 때 ReplicatedStorage.Remotes에 만든다.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local folder = Instance.new("Folder")
folder.Name = "Remotes"

local function event(name: string): RemoteEvent
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

local Remotes = {
	State = event(Config.Remotes.State), -- 서버 → 모두: 영업 상태(주문·매출·남은 시간)
	Toast = event(Config.Remotes.Toast), -- 서버 → 한 명 또는 모두: 짧은 알림
	Ready = event(Config.Remotes.Ready), -- 클라이언트 → 서버: 화면이 준비됐으니 지금 상태를 보내 달라
	Start = event(Config.Remotes.Start), -- 클라이언트 → 서버: 영업 시작(다음 날·다시 도전)
	Buy = event(Config.Remotes.Buy), -- 클라이언트 → 서버: 상점 물건 id
	IceOpen = event(Config.Remotes.IceOpen), -- 서버 → 한 명: 아이스크림 만들기 창 열기(true)·닫기(false)
	IceMake = event(Config.Remotes.IceMake), -- 클라이언트 → 서버: 만든 아이스크림(그릇·맛·토핑), 취소면 nil
	Animal = event(Config.Remotes.Animal), -- 클라이언트 → 서버: 내 동물 바꾸기
	Tutorial = event(Config.Remotes.Tutorial), -- 클라이언트 → 서버: 튜토리얼 시작(true)·그만하기(false)
	Unstuck = event(Config.Remotes.Unstuck), -- 클라이언트 → 서버: 끼었을 때 처음 자리로
	PayDebt = event(Config.Remotes.PayDebt), -- 클라이언트 → 서버: 빚 갚기(코인 수, "all"이면 전부)
	Earned = event(Config.Remotes.Earned), -- 서버 → 모두: 손님에게 낸 자리 위치, 번 코인, 팀 콤보, 낸 사람 UserId, 큰 보너스(콤보·단체)인지
	Sfx = event(Config.Remotes.Sfx), -- 서버 → 한 명 또는 모두: 효과음 이름(Config.Sounds)
	Admin = event(Config.Remotes.Admin), -- 클라이언트 → 서버: 관리자 명령("pass" = DAY 패스, "stop" = 영업 그만하기, "coins", n = 내 지갑에 코인 n). 서버가 관리자인지 확인한다
	Chat = event(Config.Remotes.Chat), -- 클라이언트 → 서버: 빠른 말풍선 번호
}

folder.Parent = ReplicatedStorage

-- player가 없으면 모두에게 보낸다
function Remotes.toast(player: Player?, text: string)
	if player then
		Remotes.Toast:FireClient(player, text)
	else
		Remotes.Toast:FireAllClients(text)
	end
end

-- 효과음(Sfx.client가 튼다). player가 없으면 모두에게
function Remotes.sfx(player: Player?, name: string)
	if player then
		Remotes.Sfx:FireClient(player, name)
	else
		Remotes.Sfx:FireAllClients(name)
	end
end

return Remotes
