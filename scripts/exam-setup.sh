#!/bin/bash
# CKA Exam Environment Setup
# Run this at the start of every exam session and every practice session.
# Source: https://github.com/theplatformlab/CKA-Certified-Kubernetes-Administrator

# --- Aliases ---
alias k='kubectl'
alias kg='kubectl get'
alias kn='kubectl config set-context --current --namespace'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgn='kubectl get nodes'
alias kd='kubectl describe'
alias kaf='kubectl apply -f'
alias kdel='kubectl delete'
alias ll='ls -lah'

alias d='docker'
alias de='docker exec'

export do='--dry-run=client -o yaml'
export now='--force --grace-period=0'

# --- kubectl bash completion ---
source <(kubectl completion bash)
complete -o default -F __start_kubectl k

# --- vim YAML config ---
cat <<'EOF' >> ~/.vimrc
set expandtab
set tabstop=2
set shiftwidth=2
set number
set autoindent
EOF

# --- etcdctl ---
export ETCDCTL_API=3

# --- Verify ---
echo "--- Setup complete ---"
k get nodes
echo "Aliases: k, kn, kgp, kgs, kgn, kd, kaf, kdel"
echo "Variables: \$do (dry-run), \$now (force delete)"
echo "etcdctl API version: $ETCDCTL_API"
