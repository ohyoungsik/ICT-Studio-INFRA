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

# mkdir -p /opt/nginx-test

# cat > /opt/nginx-test/index.html <<EOF
# <!doctype html>
# <html lang="ko">
#   <head>
#     <meta charset="utf-8">
#     <title>ICT Studio ALB Test</title>
#     <style>
#       body {
#         margin: 0;
#         min-height: 100vh;
#         display: grid;
#         place-items: center;
#         font-family: Arial, "Noto Sans KR", sans-serif;
#         background: #f4f7fb;
#         color: #1f2937;
#       }
#       main {
#         width: min(720px, calc(100% - 40px));
#         padding: 32px;
#         border: 1px solid #d8dee8;
#         border-radius: 8px;
#         background: #ffffff;
#         box-shadow: 0 12px 32px rgba(15, 23, 42, 0.08);
#       }
#       h1 {
#         margin: 0 0 20px;
#         font-size: 32px;
#       }
#       p {
#         margin: 10px 0;
#         font-size: 18px;
#         line-height: 1.6;
#       }
#       strong {
#         color: #0f766e;
#       }
#     </style>
#   </head>
#   <body>
#     <main>
#       <h1>ICT Studio ALB Test</h1>
#       <p>여기는 Private <strong>$PRIVATE_IP</strong> 서버입니다.</p>
#       <p>Instance ID: <strong>$INSTANCE_ID</strong></p>
#       <p>Availability Zone: <strong>$AZ</strong></p>
#       <p>ALB routing test success</p>
#     </main>
#   </body>
# </html>
# EOF

# echo "ok" > /opt/nginx-test/health

# docker rm -f nginx-test || true
# docker run -d \
#   --name nginx-test \
#   --restart always \
#   -p 80:80 \
#   -v /opt/nginx-test:/usr/share/nginx/html:ro \
#   nginx:latest

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
  alertmanager-discord: # discord webhook
    image: benjojo/alertmanager-discord # discord 전송용 보조 어댑터로 버전이 필요없음
    container_name: alertmanager-discord
    environment: # 서버설정 - 연동 - 웹후크
      DISCORD_WEBHOOK: "https://discord.com/api/webhooks/1511180854485979297/WmkVLKs4NRQv7c8rApwM5WxNsecD7Kyg2PRxH-NJ4hnbGtxBQ9fckZczDQapjt5WT73G"
    ports:
      - "9094:9094"
    restart: unless-stopped
    networks:
      - monitoring
  loki:
    image: grafana/loki:3.7.2
    container_name: loki
    ports:
      - "3100:3100"
    volumes:
      - ./loki/loki-config.yml:/etc/loki/loki-config.yml:ro
      - loki-data:/loki
    command: -config.file=/etc/loki/loki-config.yml
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
        port: 8080
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

cat > /opt/monitoring/prometheus/rules/traffic-alerts.yml <<'EOF'
groups:
  - name: traffic-alerts
    rules:
      - alert: HighNetworkReceiveTraffic
        expr: sum by(instance) (rate(node_network_receive_bytes_total{device!~"lo|docker.*|veth.*|br.*|br-.+|flannel.*|cni.*"}[1m])) > 100 * 1024
        for: 30s
        labels:
          severity: warning
          category: traffic
        annotations:
          summary: "서버 인바운드 트래픽 높음"
          description: "{{ $labels.instance }} 서버의 인바운드 트래픽이 30초 이상 100KB/s를 초과함"

      - alert: HighNetworkTransmitTraffic
        expr: sum by(instance) (rate(node_network_transmit_bytes_total{device!~"lo|docker.*|veth.*|br.*|br-.+|flannel.*|cni.*"}[1m])) > 100 * 1024
        for: 30s
        labels:
          severity: warning
          category: traffic
        annotations:
          summary: "서버 아웃바운드 트래픽 높음"
          description: "{{ $labels.instance }} 서버의 아웃바운드 트래픽이 30초 이상 100KB/s를 초과함"
EOF

cat > /opt/monitoring/prometheus/rules/container-alerts.yml <<'EOF'
groups:
  - name: container-alerts
    rules:
      - alert: CadvisorMetricsMissing
        expr: absent(container_cpu_usage_seconds_total{name!="", image!=""})
        for: 1m
        labels:
          severity: critical
          category: container
        annotations:
          summary: "cAdvisor 컨테이너 메트릭 수집 중단"
          description: "Prometheus에 컨테이너 CPU 메트릭이 1분 이상 들어오지 않음"

      - alert: PostgresContainerDown
        expr: absent(container_cpu_usage_seconds_total{name="postgres-main"})
        for: 30s
        labels:
          severity: critical
          category: container
        annotations:
          summary: "PostgreSQL 컨테이너 중단"
          description: "postgres-main 컨테이너 메트릭이 30초 이상 수집되지 않음"

      - alert: HighContainerCPUUsage
        expr: sum by(instance, name) (rate(container_cpu_usage_seconds_total{name!="", image!=""}[1m])) * 100 > 80
        for: 1m
        labels:
          severity: warning
          category: container
        annotations:
          summary: "컨테이너 CPU 사용률 높음"
          description: "{{ $labels.instance }} / {{ $labels.name }} 컨테이너 CPU 사용률이 1분 이상 높게 유지됨"

      - alert: HighContainerMemoryUsage
        expr: container_memory_usage_bytes{name!="", image!=""} > 500 * 1024 * 1024
        for: 1m
        labels:
          severity: warning
          category: container
        annotations:
          summary: "컨테이너 메모리 사용량 높음"
          description: "{{ $labels.instance }} / {{ $labels.name }} 컨테이너 메모리 사용량이 500MB를 초과함"
EOF

mkdir -p /opt/monitoring/alertmanager
cat > /opt/monitoring/alertmanager/alertmanager.yml <<'EOF'
global:
  resolve_timeout: 5m

route:
  receiver: "telegram"
  group_by:
    - alertname
    - instance
  group_wait: 1s
  group_interval: 10s
  repeat_interval: 1m

receivers:
  - name: "telegram"
    telegram_configs:
      - bot_token: "8619890854:AAHqDl6BFoTH2L2DEd3TXTuHgYjrxJnLhmg"
        chat_id: 8294889695
        send_resolved: true
        parse_mode: "Markdown"
        message: |
          *{{ .Status | toUpper }}* Alert

          *Alert:* {{ .CommonLabels.alertname }}
          *Severity:* {{ .CommonLabels.severity }}

          {{ range .Alerts }}
          *Instance:* {{ .Labels.instance }}
          *Job:* {{ .Labels.job }}
          *Summary:* {{ .Annotations.summary }}
          *Description:* {{ .Annotations.description }}
          {{ end }}

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

cd /opt/monitoring
docker compose up -d