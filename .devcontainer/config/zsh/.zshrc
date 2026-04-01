# ===================
# Zsh Configuration
# ===================
DOTFILES_ZSH="${0:A:h}"
if [[ -L ~/.zshrc ]]; then
    DOTFILES_ZSH="$(dirname "$(readlink ~/.zshrc)")"
fi
if [[ ! -f "$DOTFILES_ZSH/integrations.zsh" ]] && [[ -f "$HOME/.config/zsh/integrations.zsh" ]]; then
    DOTFILES_ZSH="$HOME/.config/zsh"
fi

[[ -f "$DOTFILES_ZSH/integrations.zsh" ]] && source "$DOTFILES_ZSH/integrations.zsh"
[[ -f "$DOTFILES_ZSH/aliases.zsh" ]] && source "$DOTFILES_ZSH/aliases.zsh"

# ===================
# PATH
# ===================
path_prepend "$HOME/.local/bin"

# ===================
# Local Overrides
# ===================
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
