# AGENTS.md — opencharly/charly-jetkvm

The host-side installer that provisions the **appliance-resident `charly`** on a
[JetKVM](https://jetkvm.com) IP-KVM — a 32-bit ARM (`armv7l`) appliance with a
uClibc/BusyBox userland and no package manager. It ships the release binary +
welded plugin set over the authenticated `ssh` channel (the device's `wget` does
not validate TLS).

Canonical files:

- `charly-jetkvm` — the POSIX shell tool: `install` / `verify` / `status` /
  `uninstall` / `env` / `auth`.
- `tests/run-container-bed.sh` — the end-to-end bed: a throwaway `sshd` container
  stands in for the appliance and runs `install → verify → status → uninstall`.
- `.github/workflows/ci.yml` — the gates: `sh -n`, `shellcheck`, and the
  container bed.
- `CHANGELOG/` — history (one file per CalVer release).
- `README.md` — user overview only; never agent guidance.

## Load these skills first (R0)

- `/charly-internals:repo-setup` — the org landing automation (required workflow,
  native auto-merge, tag-on-merge CalVer) and the new-repo checklist.
- `/charly-check:jetkvm` — the `jetkvm:` check/control verb and the JetKVM device
  interaction this tool feeds (`JETKVM_HOST` / `JETKVM_AUTH_TOKEN`).
- `/charly-tools:charly` — the `charly` release binary + welded plugins this tool
  installs.

## Build / validate / test

- `sh -n charly-jetkvm` — POSIX syntax check.
- `shellcheck -s sh charly-jetkvm` — lint (CI runs it).
- `tests/run-container-bed.sh` — the container bed (real `gh` download + real
  `ssh` transport against a throwaway sshd container).
- The armv7 execution proof is a live run on a real JetKVM, reported in the PR
  that changes this tool — the appliance itself is not a disposable CI target.
- The merge gate is the **org-wide** `charly/pr-validator` (required check
  `validate / validate`, defined in `opencharly/.github`); this repo carries no
  per-repo candy gate.

## Modify this repo

- The tool only READS the device (it writes files under `--prefix` and nothing
  else); power/input/media actions belong to the `jetkvm:` check verb, which
  gates every mutating method behind `allow_control`.
- `auth` obeys one rule: add only what is missing, never reset existing auth.
  Preserve that invariant.
- Downloads happen on the HOST with `gh` (TLS-validated) and are streamed over
  `ssh`; never move a download onto the device.

## Landing

- PR-only. Every change lands through a pull request; the org-required
  `charly/pr-validator` validates the diff and body and arms native auto-merge on
  PASS. Direct pushes to `main` are blocked.
- History lives in `CHANGELOG/` (written by `tag-on-merge` at merge time); the PR
  body IS the changelog.
- The authoritative rulebook is the umbrella `AGENTS.md` in
  `opencharly/opencharly` and `charly/AGENTS.md` in the charly repo. Do not
  restate its rules here.
