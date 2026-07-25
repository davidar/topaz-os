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

## Conventions

- **Every deliberate deviation from the base image gets three things:** a ledger
  entry in `system_files/usr/share/topaz-os/ledger/` (frontmatter: title, date,
  status, paths), a `topaz check` assertion where build-time verifiable
  (`cmd_check` in `system_files/usr/bin/topaz`), and a README bullet.
- Ledger entry numbers are stable; gaps from removed entries are fine.
- Prefer patching base-image files in `build_files/build.sh` (with a grep guard
  that fails loudly if upstream drifts) over shipping full replacement copies.
- Per-user configuration ships as opt-in ujust recipes in
  `system_files/usr/share/ublue-os/just/60-custom.just` (imported via the
  base's optional `60-custom.just` hook), never as baked user state.
- The image must stay analysis-tool-agnostic: the night shift's triage backend
  is user-configured (`TRIAGE_CMD`), and the image never auto-runs remote
  installers.
- This is a public repository: comments, commit messages, and docs should read
  cleanly to strangers.

## Verification checklist for changes

1. `bash -n` any edited shell scripts
2. Local `podman build` must pass the check gate
3. `podman run --rm topaz-os:test topaz ledger` — entry count and titles sane
4. Runtime-only behavior (timers, tmpfiles, presets) needs a booted image —
   note it as post-boot verification in the commit/PR description
