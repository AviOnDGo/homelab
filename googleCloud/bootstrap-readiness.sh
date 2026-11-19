#!/usr/bin/env bash
set -Eeuo pipefail

vm_name="${1:?VM name is required}"
project_id="${2:?Project ID is required}"
zone="${3:?Zone is required}"
bootstrap_max_attempts="${BOOTSTRAP_MAX_ATTEMPTS:-60}"
bootstrap_interval_seconds="${BOOTSTRAP_INTERVAL_SECONDS:-15}"

ssh_command() {
  local remote_command="$1"
  gcloud compute ssh "$vm_name" \
    --project "$project_id" \
    --zone "$zone" \
    --command "$remote_command"
}

wait_for_ssh() {
  for attempt in $(seq 1 30); do
    if ssh_command "echo ssh-ready" >/dev/null 2>&1; then
      echo "VM SSH is ready"
      return 0
    fi

    echo "Waiting for SSH readiness (attempt ${attempt}/30)"
    sleep 10
  done

  echo "Timed out waiting for SSH access to VM"
  return 1
}

print_bootstrap_diagnostics() {
  ssh_command "sudo bash -lc 'echo \"[diagnostic] bootstrap status\"; cat /var/lib/homelab-bootstrap/status 2>/dev/null || echo \"[diagnostic] status file missing\"; echo; echo \"[diagnostic] bootstrap log tail\"; tail -n 200 /var/log/homelab-bootstrap.log 2>/dev/null || echo \"[diagnostic] log file missing\"'" || true
}

read_bootstrap_status() {
  ssh_command "sudo cat /var/lib/homelab-bootstrap/status" 2>/dev/null || true
}

wait_for_bootstrap_completion() {
  local bootstrap_status
  local attempt

  for attempt in $(seq 1 "$bootstrap_max_attempts"); do
    bootstrap_status="$(read_bootstrap_status)"

    if [[ -z "$bootstrap_status" ]]; then
      echo "Bootstrap status is not readable yet (attempt ${attempt}/${bootstrap_max_attempts})"
    else
      echo "Bootstrap status (attempt ${attempt}/${bootstrap_max_attempts}): $bootstrap_status"
    fi

    if [[ "$bootstrap_status" == completed* ]]; then
      echo "Bootstrap completed successfully"
      return 0
    fi

    if [[ "$bootstrap_status" == failed* ]]; then
      print_bootstrap_diagnostics
      echo "Bootstrap reported failure; inspect /var/log/homelab-bootstrap.log from the diagnostic output above"
      return 1
    fi

    if [[ "$attempt" -lt "$bootstrap_max_attempts" ]]; then
      echo "Bootstrap is still in progress; waiting for the next readiness check"
      sleep "$bootstrap_interval_seconds"
    fi
  done

  print_bootstrap_diagnostics
  echo "Timed out waiting for bootstrap to complete after ${bootstrap_max_attempts} attempts"
  return 1
}

wait_for_ssh
print_bootstrap_diagnostics
wait_for_bootstrap_completion
