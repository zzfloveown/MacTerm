#!/bin/bash
set -euo pipefail
fixture="$(mktemp -d /tmp/macterm-linux.XXXXXXXX)"
port=40224

# 提取应用使用的同一采集脚本，通过临时 Linux sshd 在真实 /proc 上运行。
sed -n '/static let collector = #"""/,/"""#/p' Sources/MonitorCore/MonitorEngine.swift   | sed '1d;$d;s/^    //' > "$fixture/collect.sh"
bash -n "$fixture/collect.sh"
ssh-keygen -q -t ed25519 -N '' -f "$fixture/host"
ssh-keygen -q -t ed25519 -N '' -f "$fixture/client"
printf '[127.0.0.1]:%s %s\n' "$port" "$(cat "$fixture/host.pub")" > "$fixture/known_hosts"
sudo mkdir -p /run/sshd
cat > "$fixture/sshd_config" <<CONFIG
Port $port
ListenAddress 127.0.0.1
PidFile $fixture/sshd.pid
HostKey $fixture/host
AuthorizedKeysFile $fixture/client.pub
StrictModes no
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
AllowUsers $(id -un)
Subsystem sftp internal-sftp
CONFIG
sudo /usr/sbin/sshd -f "$fixture/sshd_config" -E "$fixture/sshd.log"
trap 'sudo kill "$(sudo cat "$fixture/sshd.pid")" || true' EXIT

ssh_options=(-F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$fixture/known_hosts"
    -o ConnectTimeout=5 -i "$fixture/client" -p "$port" -l "$(id -un)" 127.0.0.1)
ssh "${ssh_options[@]}" sh < "$fixture/collect.sh" > "$fixture/sample"
test "$(grep -cx __MACTERM__ "$fixture/sample")" = 8
grep -q '^cpu ' "$fixture/sample"
grep -q '^MemAvailable:' "$fixture/sample"
grep -q 'Inter-|' "$fixture/sample"
grep -q '^Filesystem' "$fixture/sample"
ssh -tt "${ssh_options[@]}" 'test -t 0 && test -t 1 && printf "PTY_OK\n"' < /dev/null | grep -q PTY_OK
ssh "${ssh_options[@]}" 'docker info --format "{{.ServerVersion}}" && docker ps --format "{{.ID}}"'
