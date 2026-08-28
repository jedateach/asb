#!/usr/bin/env bash
# Non-destructive smoke tests for asb. Safe to run on a host: creates no
# OS accounts, touches nothing outside a scratch config/home in $TMPDIR.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
ASB="$here/bin/asb"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export XDG_CONFIG_HOME="$scratch/config"

pass=0
fail=0
t() {  # t <description> <command...>
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "ok   $desc"; pass=$((pass+1))
    else
        echo "FAIL $desc"; fail=$((fail+1))
    fi
}
t_fail() {  # expect non-zero exit
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "FAIL $desc (expected failure)"; fail=$((fail+1))
    else
        echo "ok   $desc"; pass=$((pass+1))
    fi
}

t "asb --help exits 0"            "$ASB" --help
t "asb --version exits 0"         "$ASB" --version
t "asb with no args shows usage"  "$ASB"
t "help documents run"            grep -q '^  run ' <("$ASB" --help)
t "help documents shell"          grep -q '^  shell ' <("$ASB" --help)
t_fail "unknown command rejected" "$ASB" frobnicate
t_fail "unknown option rejected"  "$ASB" --frobnicate

# Config seeding
"$ASB" --help >/dev/null
t "agents.conf seeded" test -f "$XDG_CONFIG_HOME/asb/agents.conf"
t "seeded agents include claude" grep -q '^claude=' "$XDG_CONFIG_HOME/asb/agents.conf"

# Commands that need a sandbox fail cleanly without one
t_fail "add without sandbox fails"    "$ASB" add "$scratch"
t_fail "launch without sandbox fails" "$ASB" launch
t_fail "run without sandbox fails"    "$ASB" run true
t_fail "shell without sandbox fails"  "$ASB" shell
t_fail "run without a command fails"  "$ASB" run
t_fail "use unknown sandbox fails"    "$ASB" use nope
t_fail "delete unknown sandbox fails" "$ASB" -y delete nope
t_fail "invalid sandbox name rejected" "$ASB" create 'Bad Name!'

# pipefail + an early-exiting consumer = spurious SIGPIPE failures (see AGENTS.md)
t_fail "no SIGPIPE-prone pipelines in asb" \
    grep -qE '\| *(head|grep -q)' "$ASB"

# list with nothing configured
t "empty list exits 0" "$ASB" list

# ACL round-trip on this filesystem (informational for the host)
probe=$(mktemp -p "$scratch")
if setfacl -m "u:$USER:r" "$probe" 2>/dev/null; then
    t "ACL round-trip works in \$TMPDIR" grep -q "user:$USER" <(getfacl "$probe" 2>/dev/null)
else
    echo "skip ACL round-trip (filesystem does not support ACLs)"
fi

echo "$pass passed, $fail failed"
exit $((fail > 0))
