#!/usr/bin/env sh
# Install cwt: fetch cwt.sh and add a source line to your shell rc.
#   curl -fsSL https://raw.githubusercontent.com/oreid-zd/cwt/main/install.sh | sh
# Override the version (any git ref) with:  CWT_REF=v1.0.0 curl ... | sh
set -eu

OWNER_REPO="oreid-zd/cwt"
REF="${CWT_REF:-main}"
DEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/cwt"
DEST="$DEST_DIR/cwt.sh"
URL="https://raw.githubusercontent.com/$OWNER_REPO/$REF/cwt.sh"

command -v fzf >/dev/null 2>&1 || echo "warning: cwt needs fzf — install it (brew install fzf)" >&2

mkdir -p "$DEST_DIR"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$URL" -o "$DEST"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$DEST" "$URL"
else
  echo "error: need curl or wget" >&2; exit 1
fi
echo "installed cwt.sh -> $DEST ($REF)"

SRC_LINE="[ -f \"$DEST\" ] && . \"$DEST\"  # cwt"
# Only touch the rc for the shell running this installer's login shell.
case "${SHELL:-}" in
  *zsh) RC="$HOME/.zshrc" ;;
  *bash) RC="$HOME/.bashrc" ;;
  *) RC="" ;;
esac

if [ -n "$RC" ] && ! grep -qF "  # cwt" "$RC" 2>/dev/null; then
  printf '\n%s\n' "$SRC_LINE" >> "$RC"
  echo "added source line to $RC"
  echo "run:  . \"$RC\"   (or open a new shell)"
elif [ -n "$RC" ]; then
  echo "$RC already sources cwt — updated in place"
else
  echo "unknown shell; add this to your rc:"
  echo "  $SRC_LINE"
fi
