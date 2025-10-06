# repo_reset.sh
#!/usr/bin/env bash
set -euo pipefail

BR="backup-$(date +%Y%m%d-%H%M)"
echo "[i] Creating remote backup branch: $BR"
git fetch origin
git switch -c "$BR"
git push -u origin HEAD

echo
echo "Choose reset style:"
echo "  1) Keep history: delete all tracked files with a new commit"
echo "  2) Fresh history: orphan branch and force-push main"
read -rp "Enter 1 or 2: " choice

if [[ "$choice" == "1" ]]; then
  git switch main || git checkout -b main
  git ls-files -z | xargs -0 git rm -f || true
  printf "# infra-labs\n\nFresh reset on %s\n" "$(date)" > README.md
  printf ".venv/\n__pycache__/\n*.log\n*.retry\n" > .gitignore
  git add README.md .gitignore
  git commit -m "repo reset: remove all files and start fresh"
  git push
  echo "[✓] Reset complete (kept history). Backup branch: $BR"
elif [[ "$choice" == "2" ]]; then
  git switch --orphan clean-start
  git rm -rf . || true
  printf "# infra-labs\n\nFresh reset on %s\n" "$(date)" > README.md
  printf ".venv/\n__pycache__/\n*.log\n*.retry\n" > .gitignore
  git add README.md .gitignore
  git commit -m "fresh start"
  git branch -M main
  git push -f origin main
  echo "[✓] Reset complete (new history). Backup branch: $BR"
else
  echo "No action taken."
fi
