#!/usr/bin/env bash
# install.sh — link the tools into ~/.local/bin and check (optionally fetch) what they need.
#
#   ./install.sh           link bin/* into $PREFIX (default ~/.local/bin) and report missing dependencies
#   ./install.sh --deps    also download the missing ones (fzf, fd, mdcat, viu, chafa) as
#                          prebuilt Linux x86_64 binaries into $PREFIX. No root, no compiler needed.
#   --zellij               optional extra: also set up for zellij (links zbig and zpick, puts the
#                          zswitch plugin in ~/.config/zellij/plugins; with --deps also downloads
#                          zellij if you don't have it). Flags combine: --deps --zellij
#
# Links, not copies, so `git pull` in this directory updates the tools. Existing files in $PREFIX
# with the same name are never overwritten (you're told instead). Undo: ./install.sh --uninstall
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PREFIX=${PREFIX:-$HOME/.local/bin}
PLUGDIR=${XDG_CONFIG_HOME:-$HOME/.config}/zellij/plugins
deps=0; zj=0; uninstall=0
for a in "$@"; do
  case $a in
    --deps) deps=1 ;; --zellij) zj=1 ;; --uninstall) uninstall=1 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown option $a (try --help)" >&2; exit 2 ;;
  esac
done

if (( uninstall )); then
  for f in "$REPO"/bin/*; do
    t="$PREFIX/$(basename "$f")"
    [[ -L $t && $(readlink "$t") == "$f" ]] && rm "$t" && echo "removed $t"
  done
  t=$PLUGDIR/zswitch.wasm
  [[ -L $t && $(readlink "$t") == "$REPO/zellij/zswitch.wasm" ]] && rm "$t" && echo "removed $t"
  exit 0
fi

mkdir -p "$PREFIX"
echo "Linking tools into $PREFIX"
for f in "$REPO"/bin/*; do
  name=$(basename "$f"); t="$PREFIX/$name"
  [[ $name == zbig || $name == zpick ]] && (( ! zj )) && continue      # zellij-only helpers
  if [[ -L $t && $(readlink "$t") == "$f" ]]; then echo "  $name  already linked"
  elif [[ -e $t || -L $t ]]; then echo "  $name  SKIPPED: $t already exists (not ours)"
  else ln -s "$f" "$t"; echo "  $name"; fi
done
if (( zj )); then                                  # session-switch plugin used by zpick
  mkdir -p "$PLUGDIR"; f=$REPO/zellij/zswitch.wasm; t=$PLUGDIR/zswitch.wasm
  if [[ -L $t && $(readlink "$t") == "$f" ]]; then echo "  zswitch.wasm  already linked"
  elif [[ -e $t || -L $t ]]; then echo "  zswitch.wasm  SKIPPED: $t already exists (not ours)"
  else ln -s "$f" "$t"; echo "  zswitch.wasm  -> $PLUGDIR"; fi
fi

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
  "mdcat|mdcat --version|md|https://github.com/swsnr/mdcat/releases/download/mdcat-2.7.1/mdcat-2.7.1-x86_64-unknown-linux-gnu.tar.gz|mdcat-2.7.1-x86_64-unknown-linux-gnu/mdcat"
  "viu|viu --version|figs (images in Ghostty/kitty/iTerm)|https://github.com/atanunq/viu/releases/download/v1.5.1/viu-x86_64-unknown-linux-musl|-"
  "chafa|chafa --version|figs (images in terminals without image support, e.g. Alacritty, and inside zellij)|https://hpjansson.org/chafa/releases/static/chafa-1.18.3-1-x86_64-linux-gnu.tar.gz|chafa-1.18.3-1-x86_64-linux-gnu/chafa"
)
(( zj )) && DEPS+=("zellij|zellij --version|zbig, zpick and the zellij keybindings|https://github.com/zellij-org/zellij/releases/download/v0.42.2/zellij-x86_64-unknown-linux-musl.tar.gz|zellij")

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
    if (( deps )); then fetch "$url" "$inner" "$name" || missing=1; else missing=1; fi
  fi
done
command -v bsub >/dev/null || echo "  bsub    MISSING  (LSF; bq, bdone, bjstat and bjpick need it — are you on the cluster?)"
command -v python3 >/dev/null || echo "  python3 MISSING  (bjstat, bjpick, tol, relcheck)"
if [[ $(fzf --version 2>/dev/null | cut -d' ' -f1) =~ ^0\.([0-9]+) ]] && (( BASH_REMATCH[1] < 56 )); then
  echo "  fzf is older than 0.56; bjpick's live preview needs 0.56+. Run ./install.sh --deps after removing the old one from PATH, or put $PREFIX first."
fi

echo
if (( missing && ! deps )); then
  echo "Run ./install.sh --deps to download the missing ones into $PREFIX."
fi
if (( zj )); then echo "Zellij keys: paste the block from $REPO/zellij/keybindings.kdl (see README)."
else echo "Using zellij? ./install.sh --zellij adds the pop-up job picker and session switcher keys (optional)."; fi
echo "Every tool has -h."
