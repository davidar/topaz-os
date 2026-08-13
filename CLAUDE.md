# topaz-os development notes

Custom bootc image: Bluefin DX (NVIDIA open) + COSMIC + hybrid-laptop fixes.
See README.md for what the image contains.

## Commands

```bash
podman build -t topaz-os:test .          # local build; ~4 GB base pull on first run
podman run --rm topaz-os:test topaz check    # verify image matches its ledger
just build                                # template alternative (see Justfile)
git config core.hooksPath .githooks      # one-time: pre-commit lint of workflow files
```

The build fails unless `topaz check` passes (`RUN /usr/bin/topaz check` in the
Containerfile) — the image must match the claims in its provenance ledger.

## Ethos

The image is built around enforced invariants: the ledger describes every
deviation, lockfiles pin every input, `/var` ships empty, and the same
commit must rebuild to the same bytes. Reproducibility is the load-bearing
one — kept not as an end in itself but because it is the cheapest
universal anomaly detector there is. Any unexplained byte between two
builds of the same inputs is a real event that has not been root-caused
yet; chasing such bytes has surfaced silent file corruption in the build
environment, bugs in the CI substrate, and distro backport gaps that
nothing else would have caught (ledger 0020 records several). Corollaries
the repo lives by: verify the state a tool should have left rather than
trusting its exit code; treat "it passed on rerun" as a finding about
shared state, not a fix; prefer making bad states impossible (pins,
exact installs) over asserting them away — and where prevention is out of
reach, make detection loud enough to block publishing. Above all: when
something breaks, the fix lands here first, whoever's fault it is —
root-causing exists to name the owner, never to gate the repair.
Upstream gets the report as a gift, not as a dependency.

## Conventions

- **Every deliberate deviation from the base image gets two things:** a ledger
  entry in `system_files/usr/share/topaz-os/ledger/` (frontmatter: title, date,
  status, paths) and a `topaz check` assertion where build-time verifiable
  (`cmd_check` in `system_files/usr/bin/topaz`). The ledger is the
  authoritative list; README stays a thematic overview — touch it only when a
  change adds or removes a headline capability.
- Ledger entry numbers are stable; gaps from removed entries are fine.
- Prefer patching base-image files in `build_files/configure.sh` (with a grep
  guard that fails loudly if upstream drifts) over shipping full replacement
  copies. Build steps live in the script matching their layer: locked
  packages and their fixups in `install-packages.sh`, the compositor in
  `install-comp.sh`, system files and configuration in `configure.sh`.
- Userland lives in the topaz-home companion repo (ledger 0026), not in the
  image: per-user services, recipes, and installers go there and update at
  git speed. The image keeps only what needs atomic updates and rollback
  (boot path, compositor, packages) plus the `ujust topaz-home` bootstrap
  recipe in `system_files/usr/share/ublue-os/just/60-custom.just` — which
  clones and never applies; the image never auto-runs remote installers,
  and per-user state is never baked.
- This is a public repository: comments, commit messages, and docs should read
  cleanly to strangers.

## Verification checklist for changes

1. `bash -n` any edited shell scripts
2. Local `podman build` must pass the check gate
3. `podman run --rm topaz-os:test topaz ledger` — entry count and titles sane
4. Runtime-only behavior (timers, tmpfiles, presets) needs a booted image —
   note it as post-boot verification in the commit/PR description
