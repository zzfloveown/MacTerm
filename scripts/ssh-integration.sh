#!/bin/bash
set -euo pipefail

# 用 Runner 临时密钥启动仅监听回环的 OpenSSH 测试服务。
umask 077
fixture="$(mktemp -d /tmp/macterm-ci.XXXXXXXX)"
port=40222
known="$HOME/.ssh/known_hosts"
cleanup() {
    if [[ -f "$fixture/sshd.pid" ]]; then
        sudo kill "$(cat "$fixture/sshd.pid")" || true
    fi
    if [[ -f "$fixture/known_hosts.original" ]]; then
        cp "$fixture/known_hosts.original" "$known"
    else
        rm -f "$known"
    fi
    rm -rf "$fixture"
}
trap cleanup EXIT

ssh-keygen -q -t ed25519 -N '' -f "$fixture/host"
ssh-keygen -q -t ed25519 -N '' -f "$fixture/user"
ssh-keygen -q -t ed25519 -N '' -f "$fixture/wrong"
mkdir -p "$HOME/.ssh"
if [[ -f "$known" ]]; then cp "$known" "$fixture/known_hosts.original"; fi
cat > "$fixture/sshd_config" <<CONFIG
Port $port
ListenAddress 127.0.0.1
HostKey $fixture/host
PidFile $fixture/sshd.pid
AuthorizedKeysFile $fixture/user.pub
AllowUsers $(id -un)
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
PermitRootLogin no
Subsystem sftp internal-sftp
CONFIG
sudo /usr/sbin/sshd -f "$fixture/sshd_config" -E "$fixture/sshd.log"
trap 'tail -40 "$fixture/sshd.log" >&2 || true; cleanup' ERR

printf '[127.0.0.1]:%s %s\n' "$port" "$(cat "$fixture/host.pub")" >> "$known"
printf '[localhost]:%s %s\n' "$port" "$(cat "$fixture/wrong.pub")" >> "$known"
export MACTERM_TEST_FIXTURE="$fixture" MACTERM_TEST_PORT="$port" MACTERM_TEST_USER="$(id -un)"
swift test --skip-build --filter SSHIntegrationTests
