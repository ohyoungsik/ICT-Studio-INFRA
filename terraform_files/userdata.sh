#!/bin/bash
set -e

apt-get update -y
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
PRIVATE_IP=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)
AZ=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

# 아래는 모니터링 세팅
mkdir -p /opt/monitoring

cat > /opt/monitoring/docker-compose.yml <<'EOF'
services:
  prometheus:
    image: prom/prometheus:v3.12.0 # 혹시 모를 이변에 대비한 버전 고정
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes: # 로컬파일 > 컨테이너, ro = readonly
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
             # rules 파일 read
      - ./prometheus/rules:/etc/prometheus/rules:ro 
             # 수집한 데이터 저장공간
      - prometheus-data:/prometheus
    command: # prometheus 실행옵션
             # 설정파일
      - "--config.file=/etc/prometheus/prometheus.yml"
             # 메트릭 저장 위치, tsdb = time series database
      - "--storage.tsdb.path=/prometheus"
             # 이 옵션으로 prometheus 설정을 api로 다시 읽게 할 수 있다
      - "--web.enable-lifecycle"
    restart: unless-stopped # container가 죽으면 자동으로 재시작
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:13.0.1
    container_name: grafana
    ports:
      - "3000:3000"
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
    restart: unless-stopped
    networks:
      - monitoring

  alertmanager:
    image: prom/alertmanager:v0.32.1
    container_name: alertmanager
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
      - alertmanager-data:/alertmanager
    command:
      - "--config.file=/etc/alertmanager/alertmanager.yml"
      - "--storage.path=/alertmanager"
    restart: unless-stopped
    networks:
      - monitoring
  webhook-receiver:
    build:
      context: ./webhook-receiver
    container_name: webhook-receiver
    environment:
      LOKI_URL: "http://loki:3100"

      TELEGRAM_BOT_TOKEN: "8619890854:AAHqDl6BFoTH2L2DEd3TXTuHgYjrxJnLhmg"
      TELEGRAM_CHAT_ID: "8294889695"

      DISCORD_WEBHOOK_URL: "https://discord.com/api/webhooks/1511180854485979297/WmkVLKs4NRQv7c8rApwM5WxNsecD7Kyg2PRxH-NJ4hnbGtxBQ9fckZczDQapjt5WT73G"
    ports:
      - "8000:8000"
    restart: unless-stopped
    networks:
      - monitoring
  loki:
    image: grafana/loki:3.7.2
    container_name: loki
    user: "0"
    ports:
      - "3100:3100"
    volumes:
      - ./loki/loki-config.yml:/etc/loki/loki-config.yml:ro
      - loki-data:/loki
    command: -config.file=/etc/loki/loki-config.yml
    restart: unless-stopped
    networks:
      - monitoring

volumes:
  prometheus-data:
  grafana-data:
  alertmanager-data:
  loki-data:

networks: # Loki << >> alloy
  monitoring:
    driver: bridge
EOF

mkdir -p /opt/monitoring/prometheus/rules
cat > /opt/monitoring/prometheus/prometheus.yml <<'EOF'
global: # 글로벌 설정
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - "alertmanager:9093"

rule_files:
  - "/etc/prometheus/rules/*.yml"

scrape_configs: # 타겟 수집 설정
  - job_name: "prometheus"
    static_configs:
      - targets:
          - "prometheus:9090"

  - job_name: "app-server"
    ec2_sd_configs:
      - region: ap-northeast-2
        port: 9100
    relabel_configs:
      - source_labels: [__meta_ec2_tag_Role] # Role tag에서
        regex: app # app서버를 찾아서
        action: keep # 본다
      - source_labels: [__meta_ec2_tag_Name] # 찾은 node를
        target_label: instance # instance로 보이게 한다
      - source_labels: [__meta_ec2_instance_state] # 찾은 node가
        regex: running # 실행중인 것만
        action: keep # 본다

  - job_name: "app-cadvisor"
    ec2_sd_configs:
      - region: ap-northeast-2
        port: 8081
    relabel_configs:
      - source_labels: [__meta_ec2_tag_Role]
        regex: app
        action: keep
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance
      - source_labels: [__meta_ec2_instance_state]
        regex: running
        action: keep

  - job_name: "db-server"
    ec2_sd_configs:
      - region: ap-northeast-2
        port: 9100
    relabel_configs:
      - source_labels: [__meta_ec2_tag_Role]
        regex: db
        action: keep
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance
      - source_labels: [__meta_ec2_instance_state]
        regex: running
        action: keep

  - job_name: "db-cadvisor"
    ec2_sd_configs:
      - region: ap-northeast-2
        port: 8080
    relabel_configs:
      - source_labels: [__meta_ec2_tag_Role]
        regex: db
        action: keep
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance
      - source_labels: [__meta_ec2_instance_state]
        regex: running
        action: keep
EOF

cat > /opt/monitoring/prometheus/rules/node-alerts.yml <<'EOF'
groups:
  - name: node-alerts
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 1m
        labels:
          severity: warning
          category: node
        annotations:
          summary: "서버 CPU 사용률 높음"
          description: "{{ $labels.instance }} CPU 사용률이 1분 이상 80%를 초과함"
      
      - alert: HighMemoryUsage
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 80
        for: 1m
        labels:
          severity: warning
          category: node
        annotations:
          summary: "서버 메모리 사용률 높음"
          description: "{{ $labels.instance }} 메모리 사용률이 1분 이상 80%를 초과함"
  
      - alert: HighDiskUsage
        expr: (1 - node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) * 100 > 85
        for: 1m
        labels:
          severity: warning
          category: node
        annotations:
          summary: "서버 디스크 사용률 높음"
          description: "{{ $labels.instance }} {{ $labels.mountpoint }} 디스크 사용률이 85%를 초과함"
EOF

cat > /opt/monitoring/prometheus/rules/target-alerts.yml <<'EOF'
groups:
  - name: target-alerts
    rules:
      - alert: TargetDown
        expr: up == 0
        for: 30s
        labels:
          severity: critical
          category: target
        annotations:
          summary: "수집 대상 장애 발생"
          description: "{{ $labels.job }} / {{ $labels.instance }} 대상이 30초 이상 응답하지 않아 down으로 간주"
EOF

cat > /opt/monitoring/prometheus/rules/container-alerts.yml <<'EOF'
groups:
  - name: container-alerts
    rules:
      - alert: HighContainerCPUUsage
        expr: sum by(name) (rate(container_cpu_usage_seconds_total{name!=""}[5m])) * 100 > 80
        for: 1m
        labels:
          severity: warning
          category: container
        annotations:
          summary: "컨테이너 CPU 사용률 높음"
          description: "{{ $labels.name }} 컨테이너 CPU 사용률이 1분 이상 높게 유지됨"

      - alert: HighContainerMemoryUsage
        expr: container_memory_usage_bytes{name!=""} > 500 * 1024 * 1024
        for: 1m
        labels:
          severity: warning
          category: container
        annotations:
          summary: "컨테이너 메모리 사용량 높음"
          description: "{{ $labels.name }} 컨테이너 메모리 사용량이 500MB를 초과함"

      - alert: ContainerDown
        expr: absent(container_last_seen{name!=""})
        for: 30s
        labels:
          severity: critical
          category: container
        annotations:
          summary: "컨테이너 메트릭 수집 중단"
          description: "컨테이너 메트릭이 30초 이상 수집되지 않음"
EOF

mkdir -p /opt/monitoring/alertmanager
cat > /opt/monitoring/alertmanager/alertmanager.yml <<'EOF'
global:
  resolve_timeout: 5m

route:
  receiver: "webhook-receiver"
  group_by:
    - alertname
    - instance
  group_wait: 1s
  group_interval: 10s
  repeat_interval: 1m

receivers:
  - name: "webhook-receiver"
    webhook_configs:
      - url: "http://webhook-receiver:8000/alert"
        send_resolved: true

EOF

mkdir -p /opt/monitoring/loki
cat > /opt/monitoring/loki/loki-config.yml <<'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 72h

compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  delete_request_store: filesystem
EOF

mkdir -p /opt/monitoring/grafana/provisioning/datasources
cat > /opt/monitoring/grafana/provisioning/datasources/datasources.yml <<'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
EOF

mkdir -p /opt/monitoring/webhook-receiver

cat > /opt/monitoring/webhook-receiver/requirements.txt <<'EOF'
fastapi
uvicorn
requests
EOF

cat > /opt/monitoring/webhook-receiver/Dockerfile <<'EOF'
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

cat > /opt/monitoring/webhook-receiver/main.py <<'EOF'
from fastapi import FastAPI, Request
import os
import time
import requests

app = FastAPI()

LOKI_URL = os.getenv("LOKI_URL", "http://loki:3100")
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "")
DISCORD_WEBHOOK_URL = os.getenv("DISCORD_WEBHOOK_URL", "")


def query_loki(alertname="", job="", instance="", category="", limit=20):
    end_ns = int(time.time() * 1_000_000_000)
    start_ns = end_ns - (10 * 60 * 1_000_000_000)

    # TargetDown은 error 로그가 없을 수 있으니까 더 넓게 조회
    if alertname == "TargetDown":
        if "app" in job:
            query = '{role="app"} |~ "(?i)error|fail|failed|timeout|refused|unreachable|exception|critical|panic|down"'
        elif "db" in job:
            query = '{role="db"} |~ "(?i)error|fail|failed|timeout|refused|unreachable|exception|critical|panic|down"'
        else:
            query = '{role=~"app|db"} |~ "(?i)error|fail|failed|timeout|refused|unreachable|exception|critical|panic|down"'
    else:
        query = '{role=~"app|db"} |~ "(?i)error|fail|failed|timeout|refused|unreachable|exception|critical|panic"'

    params = {
        "query": query,
        "start": start_ns,
        "end": end_ns,
        "limit": limit,
        "direction": "backward",
    }

    try:
        res = requests.get(
            f"{LOKI_URL}/loki/api/v1/query_range",
            params=params,
            timeout=5,
        )
        res.raise_for_status()
        data = res.json()

        lines = []

        for stream in data.get("data", {}).get("result", []):
            labels = stream.get("stream", {})
            role = labels.get("role", "unknown")
            loki_instance = labels.get("instance", labels.get("host", "unknown"))
            container = labels.get("container_name", labels.get("container", ""))

            for _, line in stream.get("values", []):
                prefix = f"[{role} / {loki_instance}]"
                if container:
                    prefix += f"[{container}]"
                lines.append(f"{prefix} {line}")

        if not lines:
            return "최근 10분 동안 관련 로그 없음"

        return "\n".join(lines[:limit])

    except Exception as e:
        return f"Loki 조회 실패: {e}"


def send_telegram(message: str):
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return

    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"

    payload = {
        "chat_id": TELEGRAM_CHAT_ID,
        "text": message,
    }

    try:
        requests.post(url, json=payload, timeout=5)
    except Exception:
        pass


def send_discord(message: str):
    if not DISCORD_WEBHOOK_URL:
        return

    payload = {
        "content": message
    }

    try:
        requests.post(DISCORD_WEBHOOK_URL, json=payload, timeout=5)
    except Exception:
        pass


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/alert")
async def receive_alert(request: Request):
    body = await request.json()

    status = body.get("status", "unknown")
    alerts = body.get("alerts", [])

    for alert in alerts:
        labels = alert.get("labels", {})
        annotations = alert.get("annotations", {})

        alertname = labels.get("alertname", "unknown")
        severity = labels.get("severity", "unknown")
        instance = labels.get("instance", "unknown")
        job = labels.get("job", "unknown")
        category = labels.get("category", "unknown")

        summary = annotations.get("summary", "")
        description = annotations.get("description", "")

        loki_logs = query_loki(limit=10)

        message = f"""
[{status.upper()}] Alert + Loki Logs

Alert: {alertname}
Severity: {severity}
Category: {category}
Instance: {instance}
Job: {job}

Summary: {summary}
Description: {description}

최근 수집된 문제점:
{loki_logs}
"""

        send_telegram(message)
        send_discord(message)

    return {"result": "ok"}
EOF

cd /opt/monitoring
docker compose up -d
