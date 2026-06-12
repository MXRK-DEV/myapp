#!/usr/bin/env bash
# Usage: update-task-def.sh <task-def.json> <new-image-uri> <container-name>
# Outputs a register-task-definition-ready JSON on stdout.
set -euo pipefail

TASK_DEF_FILE=$1
NEW_IMAGE=$2
CONTAINER_NAME=$3

jq --arg IMAGE "$NEW_IMAGE" --arg NAME "$CONTAINER_NAME" \
  '.containerDefinitions = (.containerDefinitions | map(if .name == $NAME then .image = $IMAGE else . end))
   | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)' \
  "$TASK_DEF_FILE"
