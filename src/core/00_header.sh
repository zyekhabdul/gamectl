#!/usr/bin/env bash
# ==============================================================================
# GAMECTL - SOVEREIGN TUI GAME MANAGER & LAUNCHER (ZERO-BLOAT)
# ==============================================================================
# Lightweight, native Linux gaming hub:
# - Library scanner for local/standalone games
# - Automatic GBE Fork / runner inspection
# - Savegame snapshot rotation (auto-backup before launch)
# - Performance profile wrapper (Mesa GL thread, CPU governor)
# - 1-key sync to remote companion host via rsync over SSH
# - Live Steam Store search + ProtonDB rating via fzf
# ==============================================================================

set -uo pipefail

SELF_BIN="$(readlink -f "${BASH_SOURCE[0]}")"
GBE_X64="${GAMECTL_GBE_X64:-$HOME/.local/share/gbe-fork/regular/x64/libsteam_api.so}"
GBE_X86="${GAMECTL_GBE_X86:-$HOME/.local/share/gbe-fork/regular/x86/libsteam_api.so}"
GBE_WIN_X64="${GAMECTL_GBE_WIN_X64:-$HOME/.local/share/gbe-fork/windows/release/regular/x64/steam_api64.dll}"
GBE_WIN_X86="${GAMECTL_GBE_WIN_X86:-$HOME/.local/share/gbe-fork/windows/release/regular/x86/steam_api.dll}"

# ANSI Styling Tokens (Gamer Dark / Tokyo Night Theme)
UI_RST=$'\033[0m'
UI_BOLD=$'\033[1m'
UI_DIM=$'\033[38;5;244m'
UI_CYAN=$'\033[1;38;5;117m'
UI_ICE=$'\033[1;38;5;153m'
UI_PURPLE=$'\033[1;38;5;141m'
UI_GREEN=$'\033[1;38;5;120m'
UI_AMBER=$'\033[1;38;5;221m'
UI_RED=$'\033[1;38;5;203m'
UI_BOX=$'\033[38;5;60m'

# Pill badges for hotkeys
UI_PILL_ENTER=$'\033[1;38;5;232;48;5;117m ENTER \033[0m'
UI_PILL_CTRLI=$'\033[1;38;5;232;48;5;141m CTRL-I \033[0m'
UI_PILL_CTRLO=$'\033[1;38;5;232;48;5;221m CTRL-O \033[0m'
UI_PILL_CTRLP=$'\033[1;38;5;232;48;5;120m CTRL-P \033[0m'
UI_PILL_CTRLF=$'\033[1;38;5;232;48;5;153m CTRL-F \033[0m'
UI_PILL_CTRLD=$'\033[1;38;5;232;48;5;141m CTRL-D \033[0m'
UI_PILL_CTRLS=$'\033[1;38;5;232;48;5;117m CTRL-S \033[0m'
UI_PILL_CTRLB=$'\033[1;38;5;232;48;5;221m CTRL-B \033[0m'
UI_PILL_CTRLR=$'\033[1;38;5;232;48;5;174m CTRL-R \033[0m'
UI_PILL_CTRLK=$'\033[1;38;5;232;48;5;203m CTRL-K \033[0m'
UI_PILL_ESC=$'\033[1;38;5;232;48;5;248m ESC \033[0m'

# Central Modern FZF Configuration (Seamless transparent theme with rounded borders)
export FZF_DEFAULT_OPTS="--ansi --layout=reverse --border=rounded --info=inline-right --scrollbar=│ --prompt=' > ' --pointer='▶' --marker='*' --color='bg+:#282a36,bg:-1,spinner:#bd93f9,hl:#ff79c6' --color='fg:#f8f8f2,header:#8be9fd,info:#bd93f9,pointer:#50fa7b' --color='marker:#50fa7b,fg+:#ffffff,prompt:#bd93f9,hl+:#ff79c6' --color='border:#6272a4,label:#bd93f9,header-border:#6272a4,preview-border:#6272a4'"

