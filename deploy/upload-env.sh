#!/usr/bin/env bash
set -euo pipefail

. ./.env

ssh "${SSH_ADDRESS?}" "mkdir -p ${REMOTE_DIR?} && cat > ${REMOTE_DIR?}/.env" < ./.env
