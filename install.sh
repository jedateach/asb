#!/bin/sh
# asb installer (for the tarball distribution). POSIX sh, no dependencies.
#   sudo ./install.sh              install to /usr/local
#   sudo PREFIX=/usr ./install.sh  install to /usr
#   sudo ./install.sh uninstall    remove
set -eu

PREFIX="${PREFIX:-/usr/local}"
BINDIR="$PREFIX/bin"
MANDIR="$PREFIX/share/man/man1"
BASH_COMP_DIR="${BASH_COMP_DIR:-$PREFIX/share/bash-completion/completions}"
ZSH_COMP_DIR="${ZSH_COMP_DIR:-$PREFIX/share/zsh/site-functions}"

here=$(dirname "$0")

if [ "${1:-}" = "uninstall" ]; then
    rm -f "$BINDIR/asb" "$MANDIR/asb.1" \
          "$BASH_COMP_DIR/asb" "$ZSH_COMP_DIR/_asb"
    echo "asb uninstalled from $PREFIX"
    exit 0
fi

if [ "$(uname -s)" = Darwin ]; then
    for dep in sudo dscl; do
        command -v "$dep" >/dev/null 2>&1 || \
            echo "warning: '$dep' not found — asb requires macOS account tools and sudo" >&2
    done
else
    for dep in setfacl sudo; do
        command -v "$dep" >/dev/null 2>&1 || \
            echo "warning: '$dep' not found — install it (package: acl / sudo)" >&2
    done
fi

install -d "$BINDIR"
install -m 0755 "$here/bin/asb" "$BINDIR/asb"

if [ -f "$here/docs/asb.1" ]; then
    install -d "$MANDIR"
    install -m 0644 "$here/docs/asb.1" "$MANDIR/asb.1"
fi

install -d "$BASH_COMP_DIR" "$ZSH_COMP_DIR"
install -m 0644 "$here/completions/asb.bash" "$BASH_COMP_DIR/asb"
install -m 0644 "$here/completions/_asb" "$ZSH_COMP_DIR/_asb"

echo "asb installed to $BINDIR/asb"
echo "Shell completion installed for bash and zsh (new shells pick it up)."
echo "Get started: asb create claude-x"
