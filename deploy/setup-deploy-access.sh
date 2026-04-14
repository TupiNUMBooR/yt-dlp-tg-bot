#!/usr/bin/env bash
set -euo pipefail

. ./.env
: "${SSH_ADDRESS?}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

KEY_DIR="$SCRIPT_DIR/keys"
KEY_FILE="$KEY_DIR/github_actions"
PUB_FILE="$KEY_FILE.pub"
KNOWN_HOSTS_FILE="$KEY_DIR/known_hosts"

HOST="${SSH_ADDRESS#*@}"

mkdir -p "$KEY_DIR"

# create keys
if [ ! -f "$KEY_FILE" ]; then
  ssh-keygen -t ed25519 -C "github-actions-deploy" -f "$KEY_FILE" -N ""
fi

chmod 600 "$KEY_FILE"
chmod 644 "$PUB_FILE"

# add pubkey to server
ssh "$SSH_ADDRESS" 'mkdir -p ~/.ssh && chmod 700 ~/.ssh'
cat "$PUB_FILE" | ssh "$SSH_ADDRESS" 'cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'

# known_hosts (prefer ed25519)
ssh-keyscan -H -t ed25519 "$HOST" > "$KNOWN_HOSTS_FILE" 2>/dev/null || true

if [ ! -s "$KNOWN_HOSTS_FILE" ]; then
  ssh-keyscan -H "$HOST" > "$KNOWN_HOSTS_FILE" 2>/dev/null
fi

# WSL temp copy (only key, no system touch)
TEST_KEY="$KEY_FILE"

if grep -qi microsoft /proc/version 2>/dev/null; then
  TMP_DIR="$HOME/.ssh-gha-test"
  mkdir -p "$TMP_DIR"
  cp "$KEY_FILE" "$TMP_DIR/key"
  chmod 600 "$TMP_DIR/key"
  TEST_KEY="$TMP_DIR/key"

  echo
  echo "WSL temp key: $TEST_KEY"
fi

# test
echo
echo "Test connection:"
ssh -o BatchMode=yes \
    -i "$TEST_KEY" \
    -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" \
    "$SSH_ADDRESS" 'echo ok'

# output
echo
echo "Files:"
echo "  $KEY_FILE"
echo "  $PUB_FILE"
echo "  $KNOWN_HOSTS_FILE"

echo
echo "GitHub secrets:"
echo "SSH_ADDR = $SSH_ADDRESS"
echo "SSH_PRIVATE_KEY = contents of $KEY_FILE"
echo "SSH_KNOWN_HOSTS = contents of $KNOWN_HOSTS_FILE"
