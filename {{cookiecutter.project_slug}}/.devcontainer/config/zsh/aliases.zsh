# Zsh Aliases

# ===================
# Claude
# ===================
# Auto mode: Claude Code's built-in classifier decides which tool calls are
# safe to run without a prompt (permissions.defaultMode is "auto" in the
# bundled settings.json too — these aliases just make it explicit).
alias cca="claude --permission-mode auto"
alias ccac="claude --permission-mode auto --continue"
# Update Claude Code (native installer)
alias cu="curl -fsSL https://claude.ai/install.sh | bash"

# ===================
# GitHub Copilot CLI
# ===================
alias caat="copilot --allow-all-tools --banner"

# ===================
# Azure CLI
# ===================
# Who am I logged in as, and against which subscription/tenant?
alias azw='az account show --query "{user:user.name, subscription:name, tenant:tenantId}" -o table'

# ===================
# GitHub CLI
# ===================
alias ghw="gh auth status"

# ===================
# Git
# ===================
alias gs="git status --short --untracked-files=no"

# ===================
# Devcontainer
# ===================
alias dce="devcontainer exec --workspace-folder . zsh"
alias dcu="devcontainer up --workspace-folder ."
alias dcur="devcontainer up --workspace-folder . --remove-existing-container"
