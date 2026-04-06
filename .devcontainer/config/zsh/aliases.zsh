# Zsh Aliases

# ===================
# Claude
# ===================
alias ccc="claude --permission-mode bypassPermissions"
alias cccc="claude --permission-mode bypassPermissions --continue"
# Update Claude Code (native installer)
alias cu="curl -fsSL https://claude.ai/install.sh | bash"


# ===================
# Devcontainer
# ===================
alias dce="devcontainer exec --workspace-folder . zsh"
alias dcu="devcontainer up --workspace-folder ."
alias dcur="devcontainer up --workspace-folder . --remove-existing-container"
