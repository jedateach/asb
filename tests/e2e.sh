#!/usr/bin/env bash
# Full destructive end-to-end test for asb. RUN THIS INSIDE A DISPOSABLE
# CONTAINER OR VM — it creates and deletes OS accounts and rewrites sudoers entries.
# Expects to run as a non-root user with passwordless sudo, with asb
# already installed on PATH.
set -euo pipefail

[[ -f /.dockerenv || -n "${ASB_E2E_UNSAFE_OK:-}" ]] || {
    echo "refusing to run outside a container or disposable VM (set ASB_E2E_UNSAFE_OK=1 to override)" >&2
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
file_mode() {
    if [[ "$(uname -s)" == Darwin ]]; then
        stat -f "%Lp" "$1"
    else
        stat -c "%a" "$1"
    fi
}
account_home() {
    if [[ "$(uname -s)" == Darwin ]]; then
        dscl . -read "/Users/$1" NFSHomeDirectory | sed 's/^NFSHomeDirectory: //'
    else
        getent passwd "$1" | cut -d: -f6
    fi
}

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
sb_home=$(account_home "$SB")
check "[[ \"\$(file_mode '$sb_home')\" == 700 ]]" "home is 700" "home is $(file_mode "$sb_home")"

step "grant a project"
chmod 700 "$HOME"
mkdir -p "$HOME/project/sub"
echo "hello" > "$HOME/project/file.txt"
echo "s3cret" > "$HOME/secret.txt"    # world-readable until lockdown runs
cd "$HOME/project"
expect_ok asb add .

step "lockdown closes world-readable files and keeps grants alive"
expect_ok asb lockdown
[[ "$(file_mode "$HOME/secret.txt")" == "600" ]] || bad "secret.txt not tightened"
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

step "run and shell"
out=$(asb -s "$SB" run 'id -un; pwd')
check "grep -qx '$SB' <<< \"\$out\"" "run executes as $SB" "wrong uid: $out"
check "grep -qx '$sb_home' <<< \"\$out\"" "run starts in the sandbox home" "wrong cwd: $out"
out=$(asb -s "$SB" run echo 'two  words')
check "[[ \"\$out\" == 'two  words' ]]" "multiple args keep their quoting" "got: $out"
out=$(cd "$HOME/project" && asb -s "$SB" run --here pwd)
check "[[ \"\$out\" == '$HOME/project' ]]" "--here runs in the granted project" "wrong cwd: $out"
expect_fail bash -c "cd '$HOME/ungranted' && asb -s $SB run --here pwd"
out=$(printf 'id -un\n' | asb -s "$SB" shell 2>/dev/null)
check "grep -qx '$SB' <<< \"\$out\"" "shell runs as $SB" "shell wrong uid: $out"

step "create does not install anything without a TTY"
expect_ok asb create nettest --agent claude
# Capture, then match: piping into 'grep -q' lets grep exit on the first line
# and kills asb with SIGPIPE, which pipefail reports as a failed check.
out=$(asb list nettest 2>&1) || bad "asb list nettest failed: $out"
check "grep -q 'agent: claude' <<< \"\$out\"" "sandbox uses the claude agent" "wrong agent: $out"
check "! sudo -n -u nettest -i bash -lc 'command -v claude'" \
      "no unattended install happened" "claude was installed without a TTY"
expect_ok asb delete nettest --purge

step "list shows the grant"
out=$(asb list 2>&1) || bad "asb list failed: $out"
check "grep -q '$HOME/project' <<< \"\$out\"" "list shows grant" "grant missing from list: $out"

step "revoke"
expect_ok asb -s "$SB" remove "$HOME/project"
expect_fail as_sb "cat $HOME/project/file.txt"

step "recover re-applies grants"
cd "$HOME/project" && asb add . >/dev/null
# simulate ACL loss (backup/sync clobber); agent-owned files keep theirs
if [[ "$(uname -s)" == Darwin ]]; then
    chmod -RN "$HOME/project" 2>/dev/null || true
else
    setfacl -R -b "$HOME/project" 2>/dev/null || true
fi
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
