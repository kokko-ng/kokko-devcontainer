# Tool Integrations

# ===================
# Shell Helpers
# ===================
path_prepend() { [[ ":$PATH:" != *":$1:"* ]] && export PATH="$1:$PATH" }

# ===================
# Terminal color capabilities
# ===================
# `devcontainer exec` / `docker exec` don't forward the host terminal's env:
# COLORTERM is lost and TERM arrives as plain "xterm". Chalk-based CLIs
# (Claude Code, Copilot CLI, ...) then drop to 16-color mode and downsample
# their brand colors to the nearest ANSI color — Claude Code's orange becomes
# ANSI red, which the bundled Ghostty palette renders as maroon (#590008).
# devcontainer.json sets COLORTERM container-wide; this guard covers shells
# that reach zsh without it (older containers, plain docker exec, ssh).
# Both documented hosts (Ghostty, VS Code) are truecolor terminals.
[[ -z "$COLORTERM" ]] && export COLORTERM=truecolor
# Plain "xterm" undersells the host terminal, and a TERM with no terminfo
# entry in the container (e.g. xterm-ghostty on Debian bookworm) breaks
# less/clear. Normalize both cases to xterm-256color.
if [[ "$TERM" == xterm ]] || ! infocmp "$TERM" &>/dev/null; then
    export TERM=xterm-256color
fi

# ===================
# Oh My Zsh
# ===================
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="awesomepanda"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

[[ -f "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"

# ===================
# Ghostty Integration
# (no-op inside a devcontainer; harmless if $GHOSTTY_RESOURCES_DIR is unset)
# ===================
if [[ -n "$GHOSTTY_RESOURCES_DIR" ]]; then
    source "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
fi

# ===================
# fzf (Fuzzy Finder)
# ===================
if command -v fzf &>/dev/null; then
    source <(fzf --zsh) 2>/dev/null || true
    export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
    if command -v fd &>/dev/null; then
        export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_ALT_C_COMMAND="fd --type d --hidden --follow --exclude .git"
    fi
fi
