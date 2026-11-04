#!/bin/bash
# 코드를 검사하고 Studio에서 여는 장소 파일 두 개를 만든다: 게임(AnimalKitchen.rbxlx)과 로비(Lobby.rbxlx).
# 도구 위치: ~/.local/tools (Intel Mac용 Rojo 7.7.1, luau-lsp 1.70.1). 다른 곳에 두었으면 ROJO, LUAU_LSP를 지정한다.
set -euo pipefail
cd "$(dirname "$0")"

ROJO="${ROJO:-$HOME/.local/tools/rojo-7.7.1/rojo}"
LUAU_LSP="${LUAU_LSP:-$HOME/.local/tools/luau-lsp-1.70.1/luau-lsp}"
DEFS="${DEFS:-$HOME/.local/tools/luau-lsp-1.70.1/globalTypes.None.d.luau}"

# 두 장소는 일부 파일(src/shared, City, Records)을 같이 쓴다. 장소마다 따로 검사한다.
"$ROJO" sourcemap default.project.json --output sourcemap.json
"$ROJO" sourcemap lobby.project.json --output sourcemap.lobby.json
"$LUAU_LSP" analyze --platform=roblox --sourcemap=sourcemap.json --definitions=@roblox="$DEFS" src/shared src/server src/client
"$LUAU_LSP" analyze --platform=roblox --sourcemap=sourcemap.lobby.json --definitions=@roblox="$DEFS" src/lobby
"$ROJO" build default.project.json --output AnimalKitchen.rbxlx
"$ROJO" build lobby.project.json --output Lobby.rbxlx
echo "완료: AnimalKitchen.rbxlx, Lobby.rbxlx"
