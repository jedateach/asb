Name:           asb
Version:        0.0.0
Release:        1%{?dist}
Summary:        Run AI coding agents in kernel-enforced sandboxes
License:        MIT
URL:            https://github.com/geeknz/asb
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch
Requires:       bash acl sudo shadow-utils

%description
asb runs AI coding agents (Claude Code, Hermes, ...) as dedicated
locked-down OS accounts. Project access is granted per directory with
POSIX ACLs, so the kernel - not application config - enforces what an
agent can read or write.

%prep
%setup -q

%install
install -Dm0755 bin/asb %{buildroot}%{_bindir}/asb
install -Dm0644 docs/asb.1 %{buildroot}%{_mandir}/man1/asb.1
install -Dm0644 completions/asb.bash %{buildroot}%{_datadir}/bash-completion/completions/asb
install -Dm0644 completions/_asb %{buildroot}%{_datadir}/zsh/site-functions/_asb

%files
%{_bindir}/asb
%{_mandir}/man1/asb.1*
%{_datadir}/bash-completion/completions/asb
%{_datadir}/zsh/site-functions/_asb
%license LICENSE
%doc README.md

%changelog
* Fri Aug 28 2026 Colin Campbell <coder@colin.geek.nz> - 0.0.0-1
- See the GitHub release notes for changes.
