resource "aws_ssm_document" "queue_metric_publisher" {
  name            = "${local.name_prefix}-queue-metric-publisher"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install Redis queue CloudWatch metric publisher on the master node."
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "installQueueMetricPublisher"
        inputs = {
          runCommand = [
            <<-EOT
            set -euo pipefail

            mkdir -p /opt/redis

            cat > /opt/redis/queue-metric.env <<'ENV'
            AWS_REGION=${var.region}
            NAME_PREFIX=${local.name_prefix}
            ASG_NAME=${local.name_prefix}-app-asg
            METRIC_NAMESPACE=${var.queue_metric_namespace}
            ENVIRONMENT=${local.env}
            CONCERT_ID=${var.queue_metric_concert_id}
            REDIS_CONTAINER_NAME=redis
            SSM_REDIS_PASSWORD=/${local.name_prefix}/redis/password
            QUEUE_ZSET_KEY=queue:concert:${var.queue_metric_concert_id}:zset
            QUEUE_LIST_KEY=queue:concert:${var.queue_metric_concert_id}
            ENV
            chmod 600 /opt/redis/queue-metric.env

            cat > /opt/redis/queue-metric-publisher.sh <<'SCRIPT'
            #!/bin/bash
            set -euo pipefail

            source /opt/redis/queue-metric.env

            log() {
              echo "[$(date -Is)] $*"
            }

            redis_password="$(aws ssm get-parameter \
              --region "$AWS_REGION" \
              --name "$SSM_REDIS_PASSWORD" \
              --with-decryption \
              --query 'Parameter.Value' \
              --output text)"

            redis_cmd() {
              docker exec "$REDIS_CONTAINER_NAME" redis-cli -a "$redis_password" "$@" 2>/dev/null
            }

            queue_length="$(redis_cmd ZCARD "$QUEUE_ZSET_KEY" || true)"

            if ! [[ "$queue_length" =~ ^[0-9]+$ ]]; then
              queue_length="$(redis_cmd LLEN "$QUEUE_LIST_KEY" || true)"
            fi

            if ! [[ "$queue_length" =~ ^[0-9]+$ ]]; then
              log "Queue length is unavailable"
              exit 0
            fi

            in_service_count="$(aws autoscaling describe-auto-scaling-groups \
              --region "$AWS_REGION" \
              --auto-scaling-group-names "$ASG_NAME" \
              --query "length(AutoScalingGroups[0].Instances[?LifecycleState=='InService' && HealthStatus=='Healthy'])" \
              --output text 2>/dev/null || echo 0)"

            if ! [[ "$in_service_count" =~ ^[0-9]+$ ]] || [[ "$in_service_count" -lt 1 ]]; then
              in_service_count=1
            fi

            queue_per_instance="$(awk -v q="$queue_length" -v n="$in_service_count" 'BEGIN { printf "%.2f", q / n }')"

            aws cloudwatch put-metric-data \
              --region "$AWS_REGION" \
              --namespace "$METRIC_NAMESPACE" \
              --metric-data \
                "MetricName=QueueLength,Dimensions=[{Name=Environment,Value=$ENVIRONMENT},{Name=ConcertId,Value=$CONCERT_ID}],Unit=Count,Value=$queue_length" \
                "MetricName=QueueLengthPerInstance,Dimensions=[{Name=Environment,Value=$ENVIRONMENT},{Name=ConcertId,Value=$CONCERT_ID}],Unit=Count,Value=$queue_per_instance" \
                "MetricName=QueueLengthPerInstanceForAsg,Unit=Count,Value=$queue_per_instance"

            log "Published queue metrics length=$queue_length in_service=$in_service_count per_instance=$queue_per_instance"
            SCRIPT
            chmod 700 /opt/redis/queue-metric-publisher.sh

            cat > /etc/systemd/system/queue-metric-publisher.service <<'SERVICE'
            [Unit]
            Description=Publish Redis queue length metrics to CloudWatch
            After=docker.service network-online.target
            Wants=network-online.target

            [Service]
            Type=oneshot
            ExecStart=/opt/redis/queue-metric-publisher.sh
            SERVICE

            cat > /etc/systemd/system/queue-metric-publisher.timer <<'TIMER'
            [Unit]
            Description=Run Redis queue metric publisher every 30 seconds

            [Timer]
            OnBootSec=60s
            OnUnitActiveSec=30s
            AccuracySec=5s
            Unit=queue-metric-publisher.service

            [Install]
            WantedBy=timers.target
            TIMER

            systemctl daemon-reload
            systemctl enable --now queue-metric-publisher.timer
            systemctl start queue-metric-publisher.service || true
            EOT
          ]
        }
      }
    ]
  })
}

resource "aws_ssm_association" "queue_metric_publisher" {
  name = aws_ssm_document.queue_metric_publisher.name

  targets {
    key    = "tag:Role"
    values = ["master"]
  }

  depends_on = [aws_iam_role_policy.queue_metrics]
}
