# ===================
# Zsh Configuration
# ===================
# ${0:A:h} resolves symlinks (this file is usually reached via the ~/.zshrc
# symlink), so it lands on the bundled config directory directly.
DOTFILES_ZSH="${0:A:h}"
[[ -f "$DOTFILES_ZSH/integrations.zsh" ]] || DOTFILES_ZSH="$HOME/.config/zsh"

[[ -f "$DOTFILES_ZSH/integrations.zsh" ]] && source "$DOTFILES_ZSH/integrations.zsh"
[[ -f "$DOTFILES_ZSH/aliases.zsh" ]] && source "$DOTFILES_ZSH/aliases.zsh"

# ===================
# PATH
# ===================
# Inline, self-contained fallback — this must NOT depend on helpers defined in
# the conditionally-sourced integrations.zsh, or claude (installed to
# ~/.local/bin) silently falls off PATH whenever that file is absent.
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"

# ===================
# History
# ===================
# /commandhistory is a named volume (see devcontainer.json mounts), so shell
# history survives container rebuilds. Fall back to $HOME outside the
# container. Set AFTER oh-my-zsh (sourced via integrations.zsh) so these
# values win over its defaults.
if [[ -d /commandhistory && -w /commandhistory ]]; then
    export HISTFILE=/commandhistory/.zsh_history
else
    export HISTFILE="$HOME/.zsh_history"
fi
export HISTSIZE=50000
export SAVEHIST=50000
setopt SHARE_HISTORY        # share history across concurrent shells, live
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS

# ===================
# Local Overrides
# ===================
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
