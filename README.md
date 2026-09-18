# charly-jetkvm

Provision the **appliance-resident `charly`** on a [JetKVM](https://jetkvm.com)
IP-KVM — a 32-bit ARM (`armv7l`) appliance with a uClibc/BusyBox userland and no
package manager.

A JetKVM cannot install the distro packages: its `armv7l` userland has no
`apk`/`apt`/`rpm`, and the package feeds are amd64/arm64. So `charly` reaches it
the only way that works — the **published release binary + welded plugin set,
streamed over ssh**.

```sh
charly-jetkvm install --host root@jk.example.ts.net
charly-jetkvm verify  --host root@jk.example.ts.net
charly-jetkvm status  --host root@jk.example.ts.net
charly-jetkvm uninstall --host root@jk.example.ts.net
```

## What it installs

The release's `charly-linux-<arch>` binary plus `charly-plugins-linux-<arch>.tar.gz`
(the 12 welded per-plugin providers + their `.providers` word manifests), into
`/userdata/charly` by default:

```
/userdata/charly/charly            # the CalVer-stamped binary
/userdata/charly/plugins/          # plugin-<word> + <word>.providers
```

The arch is derived from the device's `uname -m`: `armv7l` → the release's
`armv7` assets (a statically-linked 32-bit ARM ELF). Override with `--arch`.

## Why it is host-side, and why there is no MCP server

Two facts about the device shape this tool:

- **Its `wget` does not validate TLS.** The JetKVM BusyBox build prints
  `note: TLS certificate validation not implemented`, so a download performed ON
  the device is MITM-exposed. `charly-jetkvm` therefore downloads on the HOST
  with `gh` (TLS-validated) and streams the bytes over the authenticated `ssh`
  channel. There are no published checksums on the release either, so the trusted
  channel is the integrity boundary.
- **It has ~199 MB of RAM and one core.** Running `charly mcp serve` on the
  device forked a full CLI model and exhausted memory, hanging the appliance
  during development. `charly-jetkvm` deliberately **does not install or start an
  MCP server**. The appliance gets `charly` for its local, project-less verbs
  (`version`, `doctor`, `clean`, …); driving the KVM itself is the host-side
  `jetkvm:` verb (`opencharly/plugin-jetkvm`), which talks to the device's own
  control plane directly and needs no charly on the device at all.

`install` refuses to proceed when the device reports less than `--min-free-mb`
(default 120 MiB) of `MemAvailable`, because installing into a memory-starved
system is how a prior attempt hung it.

## Flags

| flag | meaning |
|---|---|
| `--host <target>` | `ssh(1)` destination: an alias from `~/.ssh/config`, or `user@host[:port]`. Required. |
| `--version <CalVer>` | the `charly` release to install. Default: the newest published `v*` release. |
| `--prefix <path>` | install prefix ON THE DEVICE (default `/userdata/charly`). |
| `--arch <suffix>` | override the auto-detected artifact arch (`amd64`/`arm64`/`armv7`). |
| `--ssh-arg <arg>` | extra argument passed to every `ssh(1)` call (repeatable) — identity file, `-p`, `ProxyJump`, etc. |
| `--min-free-mb <N>` | `install` refuses below this much device `MemAvailable` (default 120). |
| `--yes` | skip the `uninstall` confirmation prompt. |

`CHARLY_JETKVM_GH` selects the `gh` binary (default `gh`).

### Identity file / non-default port

```sh
charly-jetkvm install --host jk.example.ts.net \
  --ssh-arg -i --ssh-arg ~/.ssh/jetkvm_ed25519 \
  --ssh-arg -p --ssh-arg 2222
```

or, more simply, put a `Host` stanza in `~/.ssh/config` and pass the alias.

## What `verify` proves

`verify` is the acceptance gate — it runs on the device and asserts the install
actually works, not that files were copied:

1. `charly version` equals the requested CalVer (the release stamps it).
2. the plugin directory holds `.providers` manifests.
3. a baked command word (`clean --help`) dispatches project-less through the
   plugin loader — this fails if the plugins cannot be connected.
4. `doctor` runs (non-fatal: an appliance with no container engine legitimately
   reports missing docker/podman, but the plugin dispatch is already proven).

## The device is not disposable

A JetKVM is a physical appliance wired into a real machine's keyboard, video and
power. `charly-jetkvm` only **reads** the device: it writes files under
`--prefix` and nothing else. There is no power/input/media action here — those
belong to the `jetkvm:` check verb, which gates every mutating method behind
`allow_control`.

## Development

```sh
sh -n charly-jetkvm          # POSIX syntax
shellcheck charly-jetkvm     # lint (CI runs this)
```

The CI workflow runs `shellcheck`, the POSIX syntax check, and an end-to-end
**container bed** (`tests/run-container-bed.sh`): a throwaway `sshd` container
stands in for the appliance, and `install` → `verify` → `status` → `uninstall`
run against it. The armv7 execution proof is the live run on a real JetKVM,
reported in the PR that changes this tool — the appliance itself is not a
disposable CI target.
