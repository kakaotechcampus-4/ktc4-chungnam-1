#!/bin/sh
set -eu

: "${SAEROK_STT_BACKUP_SSH_HOST:?SSH host is required}"
: "${SAEROK_STT_BACKUP_BIND_HOST:?private BE bind address is required}"
: "${SAEROK_STT_BACKUP_SSH_KEY_FILE:?dedicated private key file is required}"
: "${SAEROK_STT_BACKUP_KNOWN_HOSTS_FILE:?verified known_hosts file is required}"
ssh_port=${SAEROK_STT_BACKUP_SSH_PORT:-22}
ssh_user=${SAEROK_STT_BACKUP_SSH_USER:-saerok-stt-tunnel}
local_port=${SAEROK_STT_BACKUP_LOCAL_PORT:-18081}
remote_port=${SAEROK_STT_BACKUP_REMOTE_PORT:-18001}

python3 -c 'import ipaddress,sys; a=ipaddress.IPv4Address(sys.argv[1]); assert a.is_private and not a.is_unspecified and not a.is_multicast, "BE bind address must be private"' "$SAEROK_STT_BACKUP_BIND_HOST"
for port in "$ssh_port" "$local_port" "$remote_port"; do
    case "$port" in ''|*[!0-9]*) echo 'Invalid port' >&2; exit 1;; esac
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo 'Port out of range' >&2
        exit 1
    fi
done
test -r "$SAEROK_STT_BACKUP_SSH_KEY_FILE"
test -r "$SAEROK_STT_BACKUP_KNOWN_HOSTS_FILE"

exec /usr/bin/ssh -4 -F /dev/null -NT \
    -L "$SAEROK_STT_BACKUP_BIND_HOST:$local_port:127.0.0.1:$remote_port" \
    -o BatchMode=yes -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no \
    -o PreferredAuthentications=publickey -o IdentitiesOnly=yes -o IdentityAgent=none \
    -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$SAEROK_STT_BACKUP_KNOWN_HOSTS_FILE" \
    -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
    -o ForwardAgent=no -o ForwardX11=no -o LogLevel=ERROR \
    -i "$SAEROK_STT_BACKUP_SSH_KEY_FILE" -p "$ssh_port" \
    "$ssh_user@$SAEROK_STT_BACKUP_SSH_HOST"
