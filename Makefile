# asb — build, package, and test.
# VERSION is normally injected by CI (semver from conventional commits).
VERSION ?= 0.0.0
PREFIX  ?= /usr/local
DIST    := dist

.PHONY: all lint smoke install uninstall dist deb rpm pkgbuild release \
        test-deb test-tarball test-rpm test-arch test-all clean

all: lint smoke

lint:
	shellcheck bin/asb install.sh tests/smoke.sh tests/e2e.sh
	npx --yes prettier@3 --check "**/*.md"

smoke:
	bash tests/smoke.sh

install:
	PREFIX=$(PREFIX) ./install.sh

uninstall:
	PREFIX=$(PREFIX) ./install.sh uninstall

# ------------------------------------------------------------------ dist

# Source tarball: everything install.sh needs, versioned.
dist:
	rm -rf $(DIST)/asb-$(VERSION)
	mkdir -p $(DIST)/asb-$(VERSION)
	cp -r bin completions docs install.sh README.md $(DIST)/asb-$(VERSION)/
	sed -i 's/^ASB_VERSION=.*/ASB_VERSION="$(VERSION)"/' $(DIST)/asb-$(VERSION)/bin/asb
	tar -C $(DIST) -czf $(DIST)/asb-$(VERSION).tar.gz asb-$(VERSION)
	rm -rf $(DIST)/asb-$(VERSION)
	@echo "built $(DIST)/asb-$(VERSION).tar.gz"

# Hand-rolled .deb via dpkg-deb; no debhelper toolchain needed.
deb:
	rm -rf $(DIST)/debroot
	mkdir -p $(DIST)/debroot/DEBIAN \
	         $(DIST)/debroot/usr/bin \
	         $(DIST)/debroot/usr/share/man/man1 \
	         $(DIST)/debroot/usr/share/bash-completion/completions \
	         $(DIST)/debroot/usr/share/zsh/vendor-completions \
	         $(DIST)/debroot/usr/share/doc/asb
	install -m 0755 bin/asb $(DIST)/debroot/usr/bin/asb
	sed -i 's/^ASB_VERSION=.*/ASB_VERSION="$(VERSION)"/' $(DIST)/debroot/usr/bin/asb
	install -m 0644 docs/asb.1 $(DIST)/debroot/usr/share/man/man1/asb.1
	gzip -9n $(DIST)/debroot/usr/share/man/man1/asb.1
	install -m 0644 completions/asb.bash $(DIST)/debroot/usr/share/bash-completion/completions/asb
	install -m 0644 completions/_asb $(DIST)/debroot/usr/share/zsh/vendor-completions/_asb
	install -m 0644 README.md $(DIST)/debroot/usr/share/doc/asb/README.md
	sed 's/@VERSION@/$(VERSION)/' packaging/deb/control.in > $(DIST)/debroot/DEBIAN/control
	dpkg-deb --root-owner-group --build $(DIST)/debroot $(DIST)/asb_$(VERSION)_all.deb
	rm -rf $(DIST)/debroot
	@echo "built $(DIST)/asb_$(VERSION)_all.deb"

# ---------------------------------------------------------------- release

# Everything semantic-release's prepare step uploads: tarball, deb, rpm (built
# in a Fedora container), and a PKGBUILD pinned to the tarball's checksum.
URL ?= https://github.com/geeknz/asb

rpm: dist
	docker run --rm -v "$(CURDIR):/src" -w /src fedora:latest bash -c "\
	  dnf install -y rpm-build >/dev/null && \
	  mkdir -p /root/rpmbuild/SOURCES && \
	  cp $(DIST)/asb-$(VERSION).tar.gz /root/rpmbuild/SOURCES/ && \
	  sed 's/^Version:.*/Version:        $(VERSION)/' packaging/rpm/asb.spec > /tmp/asb.spec && \
	  rpmbuild -bb /tmp/asb.spec && \
	  cp /root/rpmbuild/RPMS/noarch/asb-$(VERSION)-*.rpm $(DIST)/"
	@echo "built $(DIST)/asb-$(VERSION)-*.rpm"

pkgbuild: dist
	sed -e 's/^pkgver=.*/pkgver=$(VERSION)/' \
	    -e 's|^url=.*|url="$(URL)"|' \
	    -e "s/^sha256sums=.*/sha256sums=('$$(sha256sum $(DIST)/asb-$(VERSION).tar.gz | cut -d' ' -f1)')/" \
	    packaging/aur/PKGBUILD > $(DIST)/PKGBUILD
	@echo "built $(DIST)/PKGBUILD"

release: dist deb rpm pkgbuild

# ------------------------------------------------------- dockerized e2e

test-deb: deb
	docker build -f tests/docker/Dockerfile.deb --build-arg VERSION=$(VERSION) -t asb-test-deb .
	docker run --rm asb-test-deb

test-tarball: dist
	docker build -f tests/docker/Dockerfile.tarball --build-arg VERSION=$(VERSION) -t asb-test-tarball .
	docker run --rm asb-test-tarball

test-rpm: dist
	docker build -f tests/docker/Dockerfile.rpm --build-arg VERSION=$(VERSION) -t asb-test-rpm .
	docker run --rm asb-test-rpm

test-arch: dist
	docker build -f tests/docker/Dockerfile.arch --build-arg VERSION=$(VERSION) -t asb-test-arch .
	docker run --rm asb-test-arch

test-all: test-deb test-tarball test-rpm test-arch

clean:
	rm -rf $(DIST)
