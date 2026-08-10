---
title: trim unused app-suite packages from the COSMIC install
date: 2026-08-10
status: active
paths:
  - /usr/share/topaz-os/packages.lock
---
# Trim unused app-suite packages

Fedora's `cosmic-session` welds the full application suite to the desktop:
it hard-Requires the file manager, terminal, screenshot tool, app library
and first-boot wizard, and Recommends the stock wallpaper collection. Two
of those serve no purpose in this image:

- **cosmic-initial-setup** (41 MiB): a first-boot wizard duplicates what an
  opinionated image preconfigures, and this image has never run it — the
  wizard is deliberately severed. The package was pure dead weight riding
  along on the dependency entry.
- **cosmic-wallpapers** (16 MiB): the image ships wallpaper units that
  follow the base's Bluefin day/night wallpapers instead; the COSMIC stock
  collection went unused. (The *default* wallpaper is unaffected — it comes
  from `cosmic-config-fedora`, which stays.)

Mechanism: the wallpaper collection is a weak dependency, so the build
excludes it (`--exclude=cosmic-wallpapers`, mirrored in the lockfile
generator). The wizard is a hard Require, which rpm only enforces as a
database entry: the build installs the transaction dnf resolves, then
removes the package with `rpm -e --nodeps` before the lockfile census
runs, so the lock records a closure that never contained it. dnf never
runs on the deployed image, so the dangling dependency entry in the rpm
database is inert.

The remaining suite (files, terminal, editor, store, screenshot, app
library) stays by choice — the apps are used, and no alternative delivery
channel exists yet (none of the core COSMIC apps are on Flathub as of
2026-08).

`topaz check` asserts both packages are absent; the lockfile census
(ledger 0022) independently fails the build if either ever ships again.
