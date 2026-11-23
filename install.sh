#!/usr/bin/env bash
# install.sh — link the tools into ~/.local/bin and check (optionally fetch) what they need.
#
#   ./install.sh           link bin/* into $PREFIX (default ~/.local/bin) and report missing dependencies
#   ./install.sh --deps    also download the missing ones (fzf, fd, zellij, mdcat, viu, chafa) as
#                          prebuilt Linux x86_64 binaries into $PREFIX. No root, no compiler needed.
#
# Links, not copies, so `git pull` in this directory updates the tools. Existing files in $PREFIX
# with the same name are never overwritten (you're told instead). Undo: ./install.sh --uninstall
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PREFIX=${PREFIX:-$HOME/.local/bin}
mode=${1:-}

if [[ $mode == --uninstall ]]; then
  for f in "$REPO"/bin/*; do
    t="$PREFIX/$(basename "$f")"
    [[ -L $t && $(readlink "$t") == "$f" ]] && rm "$t" && echo "removed $t"
  done
  exit 0
fi

mkdir -p "$PREFIX"
echo "Linking tools into $PREFIX"
for f in "$REPO"/bin/*; do
  name=$(basename "$f"); t="$PREFIX/$name"
  if [[ -L $t && $(readlink "$t") == "$f" ]]; then echo "  $name  already linked"
  elif [[ -e $t || -L $t ]]; then echo "  $name  SKIPPED: $t already exists (not ours)"
  else ln -s "$f" "$t"; echo "  $name"; fi
done

case ":$PATH:" in *":$PREFIX:"*) ;; *)
  echo
  echo "$PREFIX is not on your PATH. Add this to ~/.bashrc and open a new shell:"
  echo "  export PATH=\"$PREFIX:\$PATH\"" ;;
esac
export PATH="$PREFIX:$PATH"

# name | version check | what needs it | download URL | path of the binary inside the archive
DEPS=(
  "fzf|fzf --version|bjpick, figs (0.56 or newer)|https://github.com/junegunn/fzf/releases/download/v0.61.3/fzf-0.61.3-linux_amd64.tar.gz|fzf"
  "fd|fd --version|bjstat (files a job wrote), figs|https://github.com/sharkdp/fd/releases/download/v10.2.0/fd-v10.2.0-x86_64-unknown-linux-musl.tar.gz|fd-v10.2.0-x86_64-unknown-linux-musl/fd"
  "zellij|zellij --version|zbig and the keybindings (optional)|https://github.com/zellij-org/zellij/releases/download/v0.42.2/zellij-x86_64-unknown-linux-musl.tar.gz|zellij"
  "mdcat|mdcat --version|md|https://github.com/swsnr/mdcat/releases/download/mdcat-2.7.1/mdcat-2.7.1-x86_64-unknown-linux-gnu.tar.gz|mdcat-2.7.1-x86_64-unknown-linux-gnu/mdcat"
  "viu|viu --version|figs (images in Ghostty/kitty/iTerm)|https://github.com/atanunq/viu/releases/download/v1.5.1/viu-x86_64-unknown-linux-musl|-"
  "chafa|chafa --version|figs (images inside zellij and other terminals)|https://hpjansson.org/chafa/releases/static/chafa-1.18.3-1-x86_64-linux-gnu.tar.gz|chafa-1.18.3-1-x86_64-linux-gnu/chafa"
)

fetch() {   # URL INNER-PATH NAME
  local url=$1 inner=$2 name=$3 tmp
  tmp=$(mktemp -d)
  if ! curl -fsSL --retry 2 -o "$tmp/dl" "$url"; then echo "    download failed: $url"; rm -rf "$tmp"; return 1; fi
  if [[ $inner == - ]]; then mv "$tmp/dl" "$PREFIX/$name"
  else tar -xzf "$tmp/dl" -C "$tmp" && mv "$tmp/$inner" "$PREFIX/$name"; fi
  chmod +x "$PREFIX/$name"; rm -rf "$tmp"
  echo "    installed $PREFIX/$name ($("$PREFIX/$name" --version 2>&1 | head -1))"
}

echo
echo "Dependencies"
missing=0
for d in "${DEPS[@]}"; do
  IFS='|' read -r name check what url inner <<< "$d"
  if v=$($check 2>/dev/null | head -1) && [[ -n $v ]]; then
    printf '  %-7s ok   %s\n' "$name" "$v"
  else
    printf '  %-7s MISSING  (needed by %s)\n' "$name" "$what"
    if [[ $mode == --deps ]]; then fetch "$url" "$inner" "$name" || missing=1; else missing=1; fi
  fi
done
command -v bsub >/dev/null || echo "  bsub    MISSING  (LSF; bq, bdone, bjstat and bjpick need it — are you on the cluster?)"
command -v python3 >/dev/null || echo "  python3 MISSING  (bjstat, bjpick, tol)"
if [[ $(fzf --version 2>/dev/null | cut -d' ' -f1) =~ ^0\.([0-9]+) ]] && (( BASH_REMATCH[1] < 56 )); then
  echo "  fzf is older than 0.56; bjpick's live preview needs 0.56+. Run ./install.sh --deps after removing the old one from PATH, or put $PREFIX first."
fi

echo
if (( missing )) && [[ $mode != --deps ]]; then
  echo "Run ./install.sh --deps to download the missing ones into $PREFIX."
fi
echo "Zellij keys (optional): see $REPO/zellij/keybindings.kdl. Every tool has -h."
