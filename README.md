# asb — agent sandbox

Run AI coding agents (Claude Code, Hermes, …) inside kernel-enforced sandboxes on Linux.

`asb` gives each agent a dedicated locked-down OS account with an empty home directory,
then grants it access to specific project directories using POSIX ACLs. The agent can
disable every guardrail it controls; it can't disable the kernel. Your `~/.ssh`,
`~/.aws`, browser profiles, and other projects are simply `Permission denied`.

This is a Linux port of the ["second user account" approach for macOS][article].

[article]: https://medium.com/@bradnz/sandboxing-claude-code-on-macos-with-a-second-user-account-a16070e1663e

## Warnings

Read this before pointing an agent at anything you care about.

**It is a filesystem boundary, and only that.** What you get is kernel-enforced
isolation of your files: per-project, explicit, revocable grants, with a blast radius
limited to what you granted. What you do not get:

- **Network isolation.** The sandbox has full outbound network access. An agent can send
  anything it can read wherever it likes, and fetch and run arbitrary code inside the
  sandbox. Layer a firewall if exfiltration is in your threat model.
- **Protection for secrets _inside_ a granted project.** A grant is `rwX` over the whole
  tree — `.env`, tokens in `.git/config`, service keys and all. Keep them out of it.
- **Protection from the rest of the system.** A sandbox is an ordinary Linux account,
  not a container: it can still read anything world-readable (`/etc`, `/tmp`, other
  users' world-readable files) and see the process list.
- **Resistance to a real exploit.** Local privilege escalation defeats any account
  boundary. Run genuinely hostile code in a VM, not in `asb`.

**A grant is write access.** `asb add` gives `rwX` over the whole tree, `.git`
included — an agent can delete files, rewrite history, and push with whatever
credentials it finds in there. Grant work that is committed and pushed somewhere you can
recover it from.

**One sandbox is one trust domain.** Every session in a sandbox shares that account's
grants: a project granted to `claude-x` is readable by anything you ever run as
`claude-x`. Use separate sandboxes for work you want kept apart.

**Some commands change permissions on your files, in bulk, and do not remember what they
were.**

- `asb lockdown` runs `chmod -R go-rwx "$HOME"` and appends `umask 077` to your shell
  startup files. If anything else on the machine reads your home directory — a web
  server, a shared group directory, a backup agent running as another account — this
  will break it.
- `asb add` runs the same `chmod -R go-rwx` over the project before granting.
- `asb delete --purge` runs `userdel -r`: the sandbox's home directory, and anything an
  agent left in it, is gone.

**ACLs are fragile in transit.** Dropbox and most sync/backup tools, `rsync` without
`-A`, and `tar` without `--acls` drop them silently — grants then disappear with no
error and `asb launch` starts refusing. Keep sandboxed projects out of synced trees, or
run `asb recover` to re-apply every grant.

**Early software.** `asb` is one bash script that creates OS accounts and installs
sudoers rules on your machine. Read it before you run it, and run `asb doctor`
afterwards.

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
hermes=hermes --yolo
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

## License

MIT — see [LICENSE](LICENSE).
