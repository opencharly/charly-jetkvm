#!/usr/bin/env bash
# run-container-bed.sh — the disposable end-to-end proof for charly-jetkvm.
#
# A throwaway sshd CONTAINER stands in for the JetKVM (the appliance itself is
# physical and not disposable, so CI never touches it). The real `gh` release
# download and the real ssh transport run; only the remote architecture is a
# container's. This asserts the installer's full lifecycle against a live
# remote: install -> verify -> status -> uninstall, plus the failure modes
# (verify after uninstall, unreachable host).
#
# Usage: tests/run-container-bed.sh [<CalVer>]
#   Default CalVer: the newest published charly release.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
INSTALLER="$ROOT/charly-jetkvm"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION="$(gh release view --repo opencharly/charly --json tagName --jq '.tagName' | sed 's/^v//')"
fi
[ -n "$VERSION" ] || { echo "bed: cannot resolve a release CalVer" >&2; exit 1; }

ENGINE="${CHARLY_JETKVM_ENGINE:-}"
if [ -z "$ENGINE" ]; then
    if command -v docker >/dev/null 2>&1; then ENGINE=docker
    elif command -v podman >/dev/null 2>&1; then ENGINE=podman
    else echo "bed: neither docker nor podman found" >&2; exit 1; fi
fi

CONTAINER="charly-jetkvm-bed-$$"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/charly-jetkvm-bed.XXXXXX")"
# Pick a free HOST port (sshd inside always listens on 2222) so parallel/repeat
# runs never collide with each other or a leftover container.
free_port() {
    python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}
SSH_PORT="${CHARLY_JETKVM_BED_PORT:-$(free_port)}"
HOST_ALIAS="charly-jetkvm-bed"
PREFIX="/userdata/charly"

cleanup() {
    "$ENGINE" rm -f "$CONTAINER" >/dev/null 2>&1 || true
    rm -rf "$TMP"
}
trap cleanup EXIT INT TERM

echo "bed: charly $VERSION via $ENGINE (ssh port $SSH_PORT)"

# --- stand up the fake appliance -------------------------------------------
ssh-keygen -q -t ed25519 -N "" -f "$TMP/id"
cp "$TMP/id.pub" "$TMP/authorized_keys"

cat > "$TMP/entry.sh" <<'ENTRY'
#!/bin/sh
set -e
apk add --no-cache openssh >/dev/null 2>&1
ssh-keygen -A >/dev/null 2>&1
mkdir -p /root/.ssh
cp /authorized_keys /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
chown -R root:root /root/.ssh
exec /usr/sbin/sshd -D -e -p 2222
ENTRY
chmod +x "$TMP/entry.sh"

cat > "$TMP/sshconfig" <<EOF
Host $HOST_ALIAS
  HostName 127.0.0.1
  Port $SSH_PORT
  User root
  IdentityFile $TMP/id
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF

"$ENGINE" run -d --name "$CONTAINER" -p "$SSH_PORT:2222" \
    -v "$TMP/entry.sh:/entry.sh:ro" \
    -v "$TMP/authorized_keys:/authorized_keys:ro" \
    alpine:latest /entry.sh >/dev/null

# readiness: bounded probe, no sleep-and-hope.
ready=0
for _ in $(seq 1 30); do
    if ssh -F "$TMP/sshconfig" "$HOST_ALIAS" 'echo ready' >/dev/null 2>&1; then ready=1; break; fi
    sleep 1
done
[ "$ready" -eq 1 ] || { echo "bed: sshd container never became ready" >&2; "$ENGINE" logs "$CONTAINER" >&2 || true; exit 1; }
echo "bed: sshd container ready"

SSHARGS=(--ssh-arg -F --ssh-arg "$TMP/sshconfig")

# --- 1. install -------------------------------------------------------------
"$INSTALLER" install --host "$HOST_ALIAS" "${SSHARGS[@]}" \
    --version "$VERSION" --prefix "$PREFIX" --min-free-mb 10
echo "bed: PASS install"

# --- 2. verify --------------------------------------------------------------
"$INSTALLER" verify --host "$HOST_ALIAS" "${SSHARGS[@]}" --version "$VERSION" --prefix "$PREFIX"
echo "bed: PASS verify"

# --- 3. status reports the installed version --------------------------------
status_out="$("$INSTALLER" status --host "$HOST_ALIAS" "${SSHARGS[@]}" --prefix "$PREFIX")"
echo "$status_out" | grep -q "installed: $VERSION" || {
    echo "bed: status did not report installed $VERSION:" >&2; echo "$status_out" >&2; exit 1; }
echo "bed: PASS status"

# --- 4. verify FAILS after uninstall (negative control) ---------------------
"$INSTALLER" uninstall --host "$HOST_ALIAS" "${SSHARGS[@]}" --prefix "$PREFIX" --yes
if "$INSTALLER" verify --host "$HOST_ALIAS" "${SSHARGS[@]}" --version "$VERSION" --prefix "$PREFIX" >/dev/null 2>&1; then
    echo "bed: verify PASSED after uninstall — the gate does not actually assert the install" >&2
    exit 1
fi
echo "bed: PASS verify fails after uninstall"

# --- 5. unreachable host is a clean error (negative control) ----------------
if "$INSTALLER" status --host 203.0.113.1 --ssh-arg -o --ssh-arg ConnectTimeout=3 >/dev/null 2>&1; then
    echo "bed: status succeeded against an unreachable host" >&2
    exit 1
fi
echo "bed: PASS unreachable host errors cleanly"

echo "bed: ALL STEPS PASS (charly $VERSION)"
