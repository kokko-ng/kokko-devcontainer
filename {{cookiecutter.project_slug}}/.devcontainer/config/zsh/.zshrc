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
# Shared sign-ins
# ===================
# Every devcontainer shares these volumes, filled once by the host `dev`
# command (dev auth). Claude Code: a long-lived `claude setup-token` token,
# so no per-project /login. The Claude Code policy scrubs it from the
# environment of the commands an agent runs and denies reading the file.
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" && -r "$HOME/.config/claude-auth/oauth-token" ]]; then
    export CLAUDE_CODE_OAUTH_TOKEN="$(<"$HOME/.config/claude-auth/oauth-token")"
fi
# Copilot CLI: reuse the gh sign-in instead of a separate /login. Passed to
# copilot alone rather than exported, so no other process sees it.
copilot() {
    local token="${COPILOT_GITHUB_TOKEN:-}"
    [[ -n "$token" ]] || token="$(gh auth token 2>/dev/null)"
    if [[ -n "$token" ]]; then
        COPILOT_GITHUB_TOKEN="$token" command copilot "$@"
    else
        command copilot "$@"
    fi
}

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
