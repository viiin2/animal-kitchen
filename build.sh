#!/bin/bash
# 코드를 검사하고 Studio에서 여는 장소 파일(AnimalKitchen.rbxlx)을 만든다.
# 도구 위치: ~/.local/tools (Intel Mac용 Rojo 7.7.1, luau-lsp 1.70.1). 다른 곳에 두었으면 ROJO, LUAU_LSP를 지정한다.
set -euo pipefail
cd "$(dirname "$0")"

ROJO="${ROJO:-$HOME/.local/tools/rojo-7.7.1/rojo}"
LUAU_LSP="${LUAU_LSP:-$HOME/.local/tools/luau-lsp-1.70.1/luau-lsp}"
DEFS="${DEFS:-$HOME/.local/tools/luau-lsp-1.70.1/globalTypes.None.d.luau}"

"$ROJO" sourcemap default.project.json --output sourcemap.json
"$LUAU_LSP" analyze --platform=roblox --sourcemap=sourcemap.json --definitions=@roblox="$DEFS" src
"$ROJO" build default.project.json --output AnimalKitchen.rbxlx
echo "완료: AnimalKitchen.rbxlx"
