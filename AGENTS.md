# AGENTS.md

Guidance for AI coding agents working in this repository.

## What this is

`asb` (agent sandbox) runs AI coding agents as dedicated locked-down Linux accounts
("sandboxes"), granting them per-project directory access via POSIX ACLs. The kernel
enforces the boundary. It is a Linux port of the macOS "second user account" approach.

The entire tool is one bash script: `bin/asb`. Everything else is packaging, completions,
tests, and docs. Runtime dependencies are deliberately minimal: bash, coreutils, `acl`
(setfacl/getfacl), `sudo`, and `useradd`/`userdel` (passwd/shadow-utils). **Do not add
runtime dependencies** — no python, no jq, no curl. Docker is a dev-time dependency only.

## Commands

```sh
make lint          # shellcheck all scripts + prettier check on markdown
make smoke         # non-destructive tests, safe on the host (tests/smoke.sh)
make test-deb      # build .deb, install in ubuntu:24.04 container, run tests/e2e.sh
make test-tarball  # same via install.sh on debian:stable-slim
make test-rpm      # same via rpmbuild on fedora:latest
make test-arch     # same via makepkg on archlinux:base-devel
make test-all      # all four
make dist deb VERSION=x.y.z   # build release artifacts into dist/
make release VERSION=x.y.z    # all four artifacts; what CI's release step runs
```

Never run `tests/e2e.sh` on the host — it creates/deletes OS accounts and edits
sudoers. It refuses to run outside a container for that reason. To debug a single
e2e failure, rebuild that one image and run it interactively, e.g.:
`docker run --rm -it asb-test-deb bash` then `bash /usr/local/share/asb-tests/e2e.sh`.

## Architecture notes

- **Vocabulary**: the CLI's unit is the _sandbox_; the word "user" never appears in
  command names or help text. The backing OS account is an implementation detail.
- **Config**: `~/.config/asb/` — `config` (default_sandbox, default_agent),
  `agents.conf` (`name=command line`, one per line), `<sandbox>/directories` (grant
  list, one absolute path per line), `<sandbox>/config` (per-sandbox `agent=`).
- **ACL ordering is load-bearing**: on Linux the group permission bits of a file with
  an ACL _are_ the ACL mask. `chmod -R go-rwx` after `setfacl` would zero the mask and
  silently disable every grant. Always tighten (chmod) first, grant (setfacl) second.
- **Version**: `ASB_VERSION` in `bin/asb` is `0.0.0-dev` in git; real versions are
  injected at build time by the Makefile (`VERSION=`), which CI passes from
  semantic-release (`.releaserc.json`). Nothing in the repo is ever bumped by hand.

## Commit convention

Gitmoji + conventional commits, on every commit: `<emoji> <type>: <subject>`.

- `✨ feat:` new capability (minor bump) · `🐛 fix:` bug fix (patch)
- `📦 build:` packaging/Makefile · `✅ test:` tests · `📝 docs:` docs
- `♻️ refactor:` · `🔧 chore:` config/misc · `💥 feat!:` or `BREAKING CHANGE` → major bump

Releases are cut automatically on every push to `main` (no PRs in this repo): CI derives
the next semver from the commit types since the last tag, so commit types directly
control version numbers.
