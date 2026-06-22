resource "aws_ssm_document" "queue_consumer" {
  count           = var.enable_queue_consumer ? 1 : 0
  name            = "${var.name_prefix}-queue-consumer"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install a test queue consumer timer on the master node."
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "installQueueConsumer"
        inputs = {
          runCommand = [
            <<-EOT
            set -eu

            mkdir -p /opt/queue-consumer

            cat > /opt/queue-consumer/queue-consumer.env <<'ENV'
            BACKEND_BASE_URL=http://${var.alb_dns_name}
            CONCERT_ID=${var.queue_metric_concert_id}
            BATCH_SIZE=${var.queue_consumer_batch_size}
            ENV
            chmod 600 /opt/queue-consumer/queue-consumer.env

            cat > /opt/queue-consumer/queue-consumer.sh <<'SCRIPT'
            #!/bin/bash
            set -euo pipefail

            source /opt/queue-consumer/queue-consumer.env

            log() {
              echo "[$(date -Is)] $*"
            }

            payload="$(printf '{"concertId":%s,"count":%s}' "$CONCERT_ID" "$BATCH_SIZE")"

            response="$(curl -fsS \
              --max-time 10 \
              -H "Content-Type: application/json" \
              -X POST "$BACKEND_BASE_URL/api/queue/worker" \
              -d "$payload" 2>&1 || true)"

            if [[ -z "$response" ]]; then
              log "Queue consumer request failed with an empty response"
              exit 0
            fi

            log "Queue consumer response: $response"
            SCRIPT
            chmod 700 /opt/queue-consumer/queue-consumer.sh

            cat > /etc/systemd/system/queue-consumer.service <<'SERVICE'
            [Unit]
            Description=Consume Redis queue through backend worker API for scale-in validation
            After=network-online.target
            Wants=network-online.target

            [Service]
            Type=oneshot
            ExecStart=/opt/queue-consumer/queue-consumer.sh
            SERVICE

            cat > /etc/systemd/system/queue-consumer.timer <<'TIMER'
            [Unit]
            Description=Run test queue consumer on a schedule

            [Timer]
            OnBootSec=90s
            OnUnitActiveSec=${var.queue_consumer_interval_seconds}s
            AccuracySec=5s
            Unit=queue-consumer.service

            [Install]
            WantedBy=timers.target
            TIMER

            systemctl daemon-reload
            systemctl enable --now queue-consumer.timer
            systemctl start queue-consumer.service || true
            EOT
          ]
        }
      }
    ]
  })
}

resource "aws_ssm_association" "queue_consumer" {
  count = var.enable_queue_consumer ? 1 : 0
  name  = aws_ssm_document.queue_consumer[0].name

  targets {
    key    = "tag:Role"
    values = ["master"]
  }

  depends_on = [aws_ssm_document.queue_consumer]
}
