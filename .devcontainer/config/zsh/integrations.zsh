# Tool Integrations

# ===================
# Shell Helpers
# ===================
path_prepend() { [[ ":$PATH:" != *":$1:"* ]] && export PATH="$1:$PATH" }

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
