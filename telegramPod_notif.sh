#!/bin/bash

CONTAINER_NAME=$MY_NODE_NAME

ERROR_LOGS=$(kubectl logs $CONTAINER_NAME 2>&1 | grep "error\|fail")
#ERROR_LOGS=$(docker logs $CONTAINER_NAME 2>&1 | grep "error\|fail")

MAX_MESSAGE_LENGTH=1028

if [[ ! -z "$ERROR_LOGS" ]]; then
  MESSAGE="Errors found in container logs: $CONTAINER_NAME"

  # Check if message exceeds Telegram's limit
  if [[ ${#MESSAGE}${#ERROR_LOGS} -gt $MAX_MESSAGE_LENGTH ]]; then
    # Truncate logs and add truncation notice
    ERROR_LOGS_TAIL=$(echo "$ERROR_LOGS" | tail -c $((MAX_MESSAGE_LENGTH - ${#MESSAGE} - 25)))
    MESSAGE="$MESSAGE (Logs truncated) $ERROR_LOGS_TAIL"
  fi

  curl -s -X POST https://api.telegram.org/bot$BOT_TOKEN/sendMessage -d chat_id=$CHAT_ID -d text="$MESSAGE"

  if [[ $? -ne 0 ]]; then
    echo "Error sending notification via Telegram!"
  fi
fi
