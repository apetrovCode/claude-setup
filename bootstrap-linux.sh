#!/usr/bin/env bash
# Install the tools install.sh expects, on Debian/Ubuntu or Fedora/RHEL.
# Idempotent. Safe to re-run. Does not touch Claude Code itself.
#
# Required by the installer:  jq git claude
# Optional, each named where it degrades:  gh mempalace terraform-mcp-server
#                                          actionlint zizmor
set -euo pipefail

have() { command -v "$1" >/dev/null 2>&1; }
say()  { printf '==> %s\n' "$*"; }
skip() { printf '    %s already present\n' "$1"; }

if   have apt-get; then PM=apt
elif have dnf;     then PM=dnf
else echo "unsupported distro: need apt-get or dnf" >&2; exit 1
fi

pm_install() {
  case "$PM" in
    apt) sudo apt-get install -y "$@" ;;
    dnf) sudo dnf install -y "$@" ;;
  esac
}

say "refreshing package index"
case "$PM" in apt) sudo apt-get update -qq ;; dnf) : ;; esac

say "base tools"
for p in git jq curl ca-certificates; do
  have "$p" && { skip "$p"; continue; }
  pm_install "$p"
done

say "gh (GitHub CLI)"
if have gh; then skip gh
else
  if [ "$PM" = apt ]; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update -qq && pm_install gh
  else
    sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
    pm_install gh
  fi
fi

say "uv + mempalace (cross-session memory; 4 session hooks depend on it)"
have uv || curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
if have mempalace; then skip mempalace; else uv tool install mempalace; fi

say "actionlint (workflow syntax lint)"
if have actionlint; then skip actionlint
else
  bash <(curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash) >/dev/null
  mkdir -p "$HOME/.local/bin" && mv ./actionlint "$HOME/.local/bin/"
fi

say "zizmor (workflow security lint)"
if have zizmor; then skip zizmor; else uv tool install zizmor; fi

say "terraform-mcp-server"
if have terraform-mcp-server; then
  skip terraform-mcp-server
else
  echo "    not packaged for this distro — grab a release binary from"
  echo "    https://github.com/hashicorp/terraform-mcp-server/releases and put it on PATH."
  echo "    The installer skips the terraform MCP server until then."
fi

echo
echo "dcg (destructive-command guard) is NOT installed by this script."
echo "It is distributed as a standalone binary with no package source recorded."
echo "Without it this machine has no guard on destructive shell commands."
echo
echo "Done. Make sure ~/.local/bin is on PATH, then run: ./install.sh install"
