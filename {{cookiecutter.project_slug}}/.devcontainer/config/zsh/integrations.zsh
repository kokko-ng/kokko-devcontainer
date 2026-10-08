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
# ANSI red instead of orange.
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
# The prompt comes from Starship (below), baked into the image by the
# Dockerfile. An image built before that layer has no starship binary, so
# fall back to an Oh My Zsh theme there rather than a bare prompt.
if command -v starship &>/dev/null; then
    ZSH_THEME=""
else
    ZSH_THEME="awesomepanda"
fi
# 'git' plugin left out: it defines ~200 aliases. The prompt's git info comes
# from Starship (or, in the fallback, oh-my-zsh lib/git.zsh, not the plugin).
plugins=(zsh-autosuggestions zsh-syntax-highlighting)

[[ -f "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"

# ===================
# Starship prompt (config: ~/.config/starship.toml, linked by post-create.sh
# to the bundled config/starship/starship.toml)
# ===================
if command -v starship &>/dev/null; then
    eval "$(starship init zsh)"
    # Session context (Docker, Azure, gh, Claude, container, Colima) once per
    # new shell, to a terminal only; the prompt itself is one line. Cleared
    # STARSHIP_SHELL keeps the output plain ANSI, not zsh prompt escapes.
    [[ -o interactive && -t 1 ]] && STARSHIP_SHELL= starship prompt --profile context 2>/dev/null
fi

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
