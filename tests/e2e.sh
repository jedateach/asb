#!/usr/bin/env bash
# Full destructive end-to-end test for asb. RUN THIS INSIDE A CONTAINER —
# it creates and deletes OS accounts and rewrites sudoers entries.
# Expects to run as a non-root user with passwordless sudo, with asb
# already installed on PATH.
set -euo pipefail

[[ -f /.dockerenv || -n "${ASB_E2E_UNSAFE_OK:-}" ]] || {
    echo "refusing to run outside a container (set ASB_E2E_UNSAFE_OK=1 to override)" >&2
    exit 1
}
[[ "$(id -u)" -ne 0 ]] || { echo "run as a non-root user with sudo" >&2; exit 1; }

export ASB_ASSUME_YES=1
SB=agent1
fails=0
step() { echo; echo "== $*"; }
ok()   { echo "   ok: $*"; }
bad()  { echo "   FAIL: $*"; fails=$((fails+1)); }

expect_ok()   { if "$@" >/dev/null 2>&1; then ok "$*"; else bad "$* (expected success)"; fi; }
expect_fail() { if "$@" >/dev/null 2>&1; then bad "$* (expected failure)"; else ok "blocked: $*"; fi; }
check() { if eval "$1" >/dev/null 2>&1; then ok "$2"; else bad "$3"; fi; }

as_sb() { sudo -n -u "$SB" bash -c "$1"; }

step "doctor before any sandbox exists"
asb doctor || true   # informational; account checks don't apply yet

step "register a stub agent"
sudo tee /usr/local/bin/fake-agent >/dev/null <<'EOF'
#!/bin/sh
echo "fake-agent uid=$(id -un) cwd=$(pwd) args=$*"
EOF
sudo chmod 755 /usr/local/bin/fake-agent
echo "fake=fake-agent" >> "${XDG_CONFIG_HOME:-$HOME/.config}/asb/agents.conf"

step "create sandbox"
expect_ok asb create "$SB" --agent fake
expect_ok id "$SB"
expect_ok sudo -n -u "$SB" true
expect_ok sudo -n test -f "/etc/sudoers.d/asb-$SB"

step "sandbox home is private"
sb_home=$(getent passwd "$SB" | cut -d: -f6)
check "[[ \"\$(stat -c %a '$sb_home')\" == 700 ]]" "home is 700" "home is $(stat -c %a "$sb_home")"

step "grant a project"
chmod 700 "$HOME"
mkdir -p "$HOME/project/sub"
echo "hello" > "$HOME/project/file.txt"
echo "s3cret" > "$HOME/secret.txt"    # world-readable until lockdown runs
cd "$HOME/project"
expect_ok asb add .

step "lockdown closes world-readable files and keeps grants alive"
expect_ok asb lockdown
[[ "$(stat -c %a "$HOME/secret.txt")" == "600" ]] || bad "secret.txt not tightened"
check "grep -q 'umask 077' '$HOME/.bashrc'" "umask set in .bashrc" "umask missing from .bashrc"

step "sandbox can read/write the granted project"
expect_ok as_sb "cat $HOME/project/file.txt"
expect_ok as_sb "cat $HOME/project/sub/../file.txt"
expect_ok as_sb "echo made-by-agent > $HOME/project/agent.txt"
expect_ok as_sb "mkdir $HOME/project/agent-dir && echo x > $HOME/project/agent-dir/nested.txt"

step "owner can read files the sandbox created (mirror ACL / inheritance)"
expect_ok cat "$HOME/project/agent.txt"
expect_ok cat "$HOME/project/agent-dir/nested.txt"
expect_ok bash -c "echo owner-edit >> '$HOME/project/agent.txt'"

step "sandbox cannot escape the grant"
expect_fail as_sb "cat $HOME/secret.txt"
expect_fail as_sb "ls $HOME"
expect_fail as_sb "ls /root"

step "launch guard and agent execution"
out=$(cd "$HOME/project" && asb launch "$SB" fake -- --extra 2>&1) || bad "launch exited non-zero: $out"
check "grep -q 'uid=$SB' <<< \"\$out\"" "agent ran as $SB" "wrong uid: $out"
check "grep -q 'cwd=$HOME/project' <<< \"\$out\"" "agent ran in project" "wrong cwd: $out"
check "grep -q -- 'args=--extra' <<< \"\$out\"" "extra args passed" "args missing: $out"

mkdir -p "$HOME/ungranted"
expect_fail bash -c "cd '$HOME/ungranted' && asb launch $SB fake"

step "list shows the grant"
check "asb list | grep -q '$HOME/project'" "list shows grant" "grant missing from list"

step "revoke"
expect_ok asb -s "$SB" remove "$HOME/project"
expect_fail as_sb "cat $HOME/project/file.txt"

step "recover re-applies grants"
cd "$HOME/project" && asb add . >/dev/null
# simulate ACL loss (backup/sync clobber); agent-owned files keep theirs
setfacl -R -b "$HOME/project" 2>/dev/null || true
expect_fail as_sb "cat $HOME/project/file.txt"
expect_ok asb recover
expect_ok as_sb "cat $HOME/project/file.txt"

step "doctor passes with a live sandbox"
check "cd '$HOME/project' && asb doctor" "doctor clean" "doctor reported failures"

step "delete with purge"
expect_ok asb delete "$SB" --purge
expect_fail id "$SB"
expect_fail sudo -n test -f "/etc/sudoers.d/asb-$SB"

echo
if [[ $fails -eq 0 ]]; then
    echo "e2e: all checks passed"
else
    echo "e2e: $fails check(s) FAILED"
    exit 1
fi
