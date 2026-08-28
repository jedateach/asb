# asb — agent sandbox

Run AI coding agents (Claude Code, Hermes, …) inside kernel-enforced sandboxes on Linux.

`asb` gives each agent a dedicated locked-down OS account with an empty home directory,
then grants it access to specific project directories using POSIX ACLs. The agent can
disable every guardrail it controls; it can't disable the kernel. Your `~/.ssh`,
`~/.aws`, browser profiles, and other projects are simply `Permission denied`.

This is a Linux port of the ["second user account" approach for macOS][article].

[article]: https://medium.com/@bradnz/sandboxing-claude-code-on-macos-with-a-second-user-account-a16070e1663e

## Install

**Ubuntu / Debian** — download the `.deb` from the latest release:

```sh
sudo apt install ./asb_<version>_all.deb
```

**Any distro** — from the release tarball:

```sh
tar xzf asb-<version>.tar.gz
cd asb-<version>
sudo ./install.sh          # PREFIX=/usr/local by default
```

**Fedora / RHEL** — install the `.rpm` from the release.
**Arch** — a `PKGBUILD` is attached to each release (`makepkg -si`).

Runtime dependencies (present on most systems): `bash`, `acl`, `sudo`, `passwd`.

## Quick start

```sh
# One-off: stop other accounts reading your home directory
asb lockdown

# Create a sandbox (a locked-down OS account) and make it the default.
# It offers to install the agent CLI inside the sandbox for you.
asb create claude-x --agent claude

# Grant it a project and launch
cd ~/code/my-project
asb add
asb launch
```

Day to day:

```sh
asb launch                     # default sandbox, its default agent, right here
asb launch claude-x            # a specific sandbox
asb launch claude-x hermes -- --continue   # explicit agent + pass-through args
asb run 'claude --version'     # run any command as the sandbox, in its home
asb shell                      # an interactive shell inside the sandbox
asb list                       # every sandbox and what it can touch
asb remove                     # revoke the current project
asb doctor                     # check ACLs, sudoers, agents
```

`launch` refuses to run unless the current directory has been granted — a guard against
starting an agent somewhere it has no business being.

## Agents

Agents are defined in `~/.config/asb/agents.conf`, one per line:

```
claude=claude --dangerously-skip-permissions
claude-safe=claude
hermes=hermes
```

Whether an agent runs with its own permission prompts disabled is your per-agent choice.
The OS boundary holds either way — that's the point.

An agent's CLI has to be installed _inside_ the sandbox, where your own copy is out of
reach. `asb create` offers to do that for agents it knows how to fetch (Claude Code
today); `--install` installs without asking, `--no-install` skips it, and nothing is ever
installed non-interactively (or by `-y`) unless you pass `--install`. For anything else,
install it yourself with one command:

```sh
asb -s claude-x run 'curl -fsSL https://example.com/install.sh | bash'
asb -s claude-x shell          # or poke around by hand
```

## How it works

- `asb create <name>` makes a standard OS account with a `700` home and installs a
  scoped sudoers rule (`you ALL=(<name>) NOPASSWD: ALL`) — a one-way, passwordless door
  into the sandbox. The sandbox gets no sudo rights of its own.
- `asb add` tightens the project (`chmod -R go-rwx`), grants the sandbox `rwX` with
  inheriting default ACLs (`setfacl`), gives it traverse-only (`--x`) permission on
  parent directories, and warns if a world-readable parent would leak sibling names.
- `asb launch` re-checks the grant list, then runs the agent as the sandbox account in
  your current directory. `asb run` and `asb shell` use the same door for anything else
  you need to do inside the sandbox (installing an agent, checking a version).
- Grants live in `~/.config/asb/<sandbox>/directories`; `asb recover` re-applies them
  all after anything that strips ACLs.

## What this buys you (and what it doesn't)

You get filesystem isolation enforced by the kernel, per-project explicit revocable
grants, and a blast radius limited to what you granted.

You don't get network isolation (layer a firewall if exfiltration is in your threat
model), protection for secrets _inside_ granted projects (keep them out of the tree),
or resistance to kernel privilege-escalation exploits (use a VM for hostile code).

**Sync-service caveat**: Dropbox and most backup tools do not preserve POSIX ACLs. Keep
sandboxed projects outside synced trees, or run `asb recover` when grants go missing.
