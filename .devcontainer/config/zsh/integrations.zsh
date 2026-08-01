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
# fzf and fd-find are installed by the Dockerfile via apt. Debian quirks:
# the fd binary ships as `fdfind`, and bookworm's fzf predates the `--zsh`
# flag — fall back to the packaged keybinding scripts in that case.
if command -v fzf &>/dev/null; then
    if fzf --zsh &>/dev/null; then
        source <(fzf --zsh)
    else
        [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]] && source /usr/share/doc/fzf/examples/key-bindings.zsh
        [[ -f /usr/share/doc/fzf/examples/completion.zsh ]] && source /usr/share/doc/fzf/examples/completion.zsh
    fi
    export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
    FD_BIN=""
    if command -v fd &>/dev/null; then
        FD_BIN="fd"
    elif command -v fdfind &>/dev/null; then
        FD_BIN="fdfind"
    fi
    if [[ -n "$FD_BIN" ]]; then
        export FZF_DEFAULT_COMMAND="$FD_BIN --type f --hidden --follow --exclude .git"
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_ALT_C_COMMAND="$FD_BIN --type d --hidden --follow --exclude .git"
    fi
    unset FD_BIN
fi
