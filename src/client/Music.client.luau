--!strict
-- 배경 음악: 이 게임용으로 직접 만든 8마디 멜로디(다장조, 뮤직박스 느낌)를 기본 '띵' 소리(Config.Music.sample)의
-- 높낮이(PlaybackSpeed)를 바꿔 연주한다. 남의 곡을 쓰지 않아 저작권 걱정이 없다.
-- 화음 진행 C - Am - F - G - C - Am - F·G - C, 멜로디는 8분음표, 베이스는 "쿵-짝"(근음·5음).
-- Config.Music.trackId에 Creator Store의 로블록스 라이선스 음악 id를 넣으면 그 곡을 대신 반복한다.
-- 화면 오른쪽 🎵 버튼(Hud)이 LocalPlayer 속성 MusicOff를 바꿔 켜고 끈다.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage.Shared.Config)

local player = Players.LocalPlayer
local music = Config.Music

local folder = Instance.new("Folder")
folder.Name = "KitchenMusic"
folder.Parent = SoundService

local function muted(): boolean
	return player:GetAttribute("MusicOff") == true
end

-- 라이선스 곡을 쓰는 경우: 한 곡을 반복
if music.trackId ~= "" then
	local track = Instance.new("Sound")
	track.SoundId = music.trackId
	track.Looped = true
	track.Volume = 0.35 * music.volume
	track.Parent = folder
	local function apply()
		if muted() then
			track:Pause()
		elseif not track.IsPlaying then
			track:Play()
		end
	end
	player:GetAttributeChangedSignal("MusicOff"):Connect(apply)
	apply()
	return
end

-- ── 직접 만든 멜로디 ──
-- 숫자는 도(C)에서 반음 단위, nil은 쉼표. 한 마디 = 8분음표 8개.
local N = nil
local MELODY: { number? } = {
	4, 7, 12, 7, 4, 7, 9, 7, -- C
	9, 12, 16, 12, 9, 7, 4, 2, -- Am
	5, 9, 12, 9, 5, 9, 12, 14, -- F
	14, 11, 7, 11, 14, 11, 7, N, -- G
	7, 4, 7, 12, 16, 14, 12, N, -- C
	9, 12, 16, 14, 12, 9, 4, N, -- Am
	5, 9, 12, 14, 14, 11, 7, N, -- F → G
	12, N, 7, N, 12, N, N, N, -- C
}
-- 마디마다 두 박자씩의 근음(반음, 낮은 도 기준)
local ROOTS = { 0, 0, -3, -3, -7, -7, -5, -5, 0, 0, -3, -3, -7, -5, 0, 0 }

local MELODY_SHIFT = -12 -- 멜로디 음 높이(기본 소리가 높아서 한 옥타브 내린다)
local BASS_SHIFT = -24
local POOL = 10 -- 동시에 울리는 소리 수

local voices: { Sound } = {}
for i = 1, POOL do
	local sound = Instance.new("Sound")
	sound.Name = `Voice{i}`
	sound.SoundId = music.sample
	sound.Parent = folder
	voices[i] = sound
end
local nextVoice = 1

local function note(semitones: number, volume: number)
	local sound = voices[nextVoice]
	nextVoice = nextVoice % POOL + 1
	sound.PlaybackSpeed = 2 ^ (semitones / 12)
	sound.Volume = volume * music.volume
	sound.TimePosition = 0
	sound:Play()
end

local stepSeconds = 60 / music.bpm / 2 -- 8분음표
local step = 0
local elapsed = 0

RunService.Heartbeat:Connect(function(dt: number)
	if muted() then
		return
	end
	elapsed += dt
	while elapsed >= stepSeconds do
		elapsed -= stepSeconds
		local index = step % #MELODY + 1
		local pitch = MELODY[index]
		if pitch then
			note(pitch + MELODY_SHIFT, 0.22)
		end
		-- 베이스: 박의 처음(8분음표 0·4번째)에 근음, 2·6번째에 5음을 작게
		local inBar = step % 8
		local root = ROOTS[(step // 4) % #ROOTS + 1]
		if inBar == 0 or inBar == 4 then
			note(root + BASS_SHIFT, 0.16)
		elseif inBar == 2 or inBar == 6 then
			note(root + 7 + BASS_SHIFT, 0.09)
		end
		step += 1
	end
end)
