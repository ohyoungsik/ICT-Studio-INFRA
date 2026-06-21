# ==============================================
# Security Group 규칙
# ==============================================
# 트래픽 흐름: 사용자 → ALB → App Server → DB Server
# 같이 단방향 접근만 허용고 기타 모든 접근은 차단

resource "aws_security_group_rule" "bastion_ingress_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion.id
  description       = "SSH access to bastion host"
}

resource "aws_security_group_rule" "bastion_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion.id
  description       = "Bastion outbound all traffic"
}

resource "aws_security_group_rule" "app_ingress_ssh_from_bastion" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.app.id
  description              = "SSH from bastion to app servers"
}

resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "Public HTTP access for ALB"
}

resource "aws_security_group_rule" "alb_ingress_portainer" {
  type              = "ingress"
  from_port         = 9000
  to_port           = 9000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "Public Portainer HTTP access via ALB"
}

resource "aws_security_group_rule" "alb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "ALB outbound all traffic"
}

resource "aws_security_group_rule" "app_ingress_http" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.app.id
  description              = "ALB to App HTTP"
}

resource "aws_security_group_rule" "app_ingress_app_port" {
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.app.id
  description              = "ALB to App custom port"
}

resource "aws_security_group_rule" "app_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app.id
  description       = "App outbound all traffic"
}

resource "aws_security_group_rule" "db_ingress_ssh_from_bastion" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.db.id
  description              = "SSH from bastion to DB servers"
}

# DB Main ↔ DB Replica 간 복제 통신 (향후 Replica 추가 시 사용)
resource "aws_security_group_rule" "db_ingress_postgres_self" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.db.id
  security_group_id        = aws_security_group.db.id
  description              = "DB internal replication (Main - Replica)"
}

resource "aws_security_group_rule" "db_ingress_postgres" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.db.id
  description              = "App to DB Postgres access"
}

resource "aws_security_group_rule" "db_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.db.id
  description       = "DB outbound all traffic"
}

# --- Postgres HA --- PostgreSQL HA 전용 Docker Swarm 내부 통신 규칙이다.
# --- Postgres HA --- DB 노드끼리 Docker Swarm manager/worker 제어 통신을 하기 위한 2377/tcp 허용이다.
resource "aws_security_group_rule" "db_ingress_swarm_management_self" {
  type                     = "ingress"
  from_port                = 2377
  to_port                  = 2377
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.db.id
  security_group_id        = aws_security_group.db.id
  description              = "PostgreSQL HA Swarm management between DB nodes"
}

# --- Postgres HA --- DB 노드 간 Swarm gossip TCP 통신을 위한 7946/tcp 허용이다.
resource "aws_security_group_rule" "db_ingress_swarm_gossip_tcp_self" {
  type                     = "ingress"
  from_port                = 7946
  to_port                  = 7946
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.db.id
  security_group_id        = aws_security_group.db.id
  description              = "PostgreSQL HA Swarm gossip TCP between DB nodes"
}

# --- Postgres HA --- DB 노드 간 Swarm gossip UDP 통신을 위한 7946/udp 허용이다.
resource "aws_security_group_rule" "db_ingress_swarm_gossip_udp_self" {
  type                     = "ingress"
  from_port                = 7946
  to_port                  = 7946
  protocol                 = "udp"
  source_security_group_id = aws_security_group.db.id
  security_group_id        = aws_security_group.db.id
  description              = "PostgreSQL HA Swarm gossip UDP between DB nodes"
}

# --- Postgres HA --- DB 노드 간 overlay network VXLAN 통신을 위한 4789/udp 허용이다.
resource "aws_security_group_rule" "db_ingress_swarm_overlay_self" {
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  source_security_group_id = aws_security_group.db.id
  security_group_id        = aws_security_group.db.id
  description              = "PostgreSQL HA Swarm overlay network between DB nodes"
}

# --- Postgres HA --- 운영자가 Bastion을 통해 HAProxy stats 포트에 접근할 수 있게 한다.
resource "aws_security_group_rule" "db_ingress_haproxy_stats_from_bastion" {
  type                     = "ingress"
  from_port                = 8404
  to_port                  = 8405
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.db.id
  description              = "HAProxy stats access from bastion"
}

# ==============================================
# Docker Swarm Security Group 규칙
# ==============================================
# 아키텍처: Manager(고정 EC2, master_node SG) + Worker(ASG, app SG)
# Swarm 필수 포트: 2377/tcp(관리), 7946/tcp·udp(gossip), 4789/udp(overlay)

# ── Master Node SG ─────────────────────────────

# 역할: Bastion 경유 SSH 관리 접속
# 용도: 프라이빗 서브넷의 manager에 운영자가 접속해 swarm/docker 명령 실행
# 흐름: Bastion → Manager:22
resource "aws_security_group_rule" "master_ingress_ssh_from_bastion" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.master_node.id
  description              = "SSH from bastion to swarm manager"
}

# 역할: Bastion 경유 Portainer 웹 UI 접속
# 용도: 운영자가 Bastion에서 SSH 터널(-L)로 manager의 Portainer에 접근
# 포트: 8001(Edge), 9000(HTTP), 9443(HTTPS)
# 흐름: Local PC → Bastion(SSH tunnel) → Manager:8001|9000|9443
resource "aws_security_group_rule" "master_ingress_portainer_from_bastion" {
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 9443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.master_node.id
  description              = "Portainer UI from bastion (8001, 9000, 9443)"
}

# 역할: ALB → Portainer 웹 UI (외부 직접 접속)
# 용도: 인터넷 → ALB:9000 → Manager:9000
# 흐름: User → ALB → Manager Portainer HTTP
resource "aws_security_group_rule" "master_ingress_portainer_from_alb" {
  type                     = "ingress"
  from_port                = 9000
  to_port                  = 9000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.master_node.id
  description              = "Portainer HTTP from ALB"
}

# 역할: Redis (대기열·캐시)
# 용도: ASG worker의 FastAPI가 master Redis에 접속
# 흐름: Worker(app SG) → Manager:6379
resource "aws_security_group_rule" "master_ingress_redis_from_workers" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.master_node.id
  description              = "Redis from app workers"
}

# 역할: Swarm 클러스터 관리 API (Control Plane)
# 용도: worker의 `swarm join`, heartbeat, task 스케줄링 명령 수신
# 흐름: Worker(app SG) → Manager:2377
# 비고: 이 포트가 막히면 worker join 및 클러스터 heartbeat 실패
resource "aws_security_group_rule" "master_ingress_swarm_management_from_workers" {
  type                     = "ingress"
  from_port                = 2377
  to_port                  = 2377
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.master_node.id
  description              = "Swarm cluster management from workers"
}

# 역할: Swarm manager 간 Raft/consensus 통신 (향후 manager 다중화 시)
# 용도: manager 3대 구성 시 leader 선출, 클러스터 상태 복제
# 흐름: Manager → Manager:2377
resource "aws_security_group_rule" "master_ingress_swarm_management_self" {
  type                     = "ingress"
  from_port                = 2377
  to_port                  = 2377
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.master_node.id
  security_group_id        = aws_security_group.master_node.id
  description              = "Swarm cluster management between managers"
}

# 역할: Swarm 노드 디스커버리 - Gossip (TCP)
# 용도: 클러스터 멤버 목록·overlay 멤버십 정보 교환
# 흐름: Worker → Manager:7946 (양방향 gossip의 수신 측)
resource "aws_security_group_rule" "master_ingress_swarm_gossip_tcp_from_workers" {
  type                     = "ingress"
  from_port                = 7946
  to_port                  = 7946
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.master_node.id
  description              = "Swarm node discovery TCP from workers"
}

# 역할: Swarm manager 간 Gossip (TCP) - 향후 manager 다중화 시
# 흐름: Manager → Manager:7946
resource "aws_security_group_rule" "master_ingress_swarm_gossip_tcp_self" {
  type                     = "ingress"
  from_port                = 7946
  to_port                  = 7946
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.master_node.id
  security_group_id        = aws_security_group.master_node.id
  description              = "Swarm node discovery TCP between managers"
}

# 역할: Swarm 노드 디스커버리 - Gossip (UDP)
# 용도: TCP와 동일 목적의 gossip 프로토콜 (UDP 채널)
# 흐름: Worker → Manager:7946
resource "aws_security_group_rule" "master_ingress_swarm_gossip_udp_from_workers" {
  type                     = "ingress"
  from_port                = 7946
  to_port                  = 7946
  protocol                 = "udp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.master_node.id
  description              = "Swarm node discovery UDP from workers"
}

# 역할: Swarm manager 간 Gossip (UDP) - 향후 manager 다중화 시
# 흐름: Manager → Manager:7946
resource "aws_security_group_rule" "master_ingress_swarm_gossip_udp_self" {
  type                     = "ingress"
  from_port                = 7946
  to_port                  = 7946
  protocol                 = "udp"
  source_security_group_id = aws_security_group.master_node.id
  security_group_id        = aws_security_group.master_node.id
  description              = "Swarm node discovery UDP between managers"
}

# 역할: Swarm Overlay Network (VXLAN 데이터 plane)
# 용도: 노드 간 컨테이너 트래픽 터널링 (다른 AZ worker 간 서비스 통신)
# 흐름: Worker → Manager:4789
resource "aws_security_group_rule" "master_ingress_swarm_overlay_from_workers" {
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.master_node.id
  description              = "Swarm overlay network from workers"
}

# 역할: Swarm manager 간 Overlay (UDP) - 향후 manager 다중화 시
# 흐름: Manager → Manager:4789
resource "aws_security_group_rule" "master_ingress_swarm_overlay_self" {
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  source_security_group_id = aws_security_group.master_node.id
  security_group_id        = aws_security_group.master_node.id
  description              = "Swarm overlay network between managers"
}

# 역할: Manager 아웃바운드 전체 허용
# 용도: NAT Gateway 경유 Docker Hub/ECR pull, apt, SSM, package download
# 비고: manager는 ALB 대상이 아니므로 ingress는 SSH + Swarm + Bastion→Portainer만 최소 개방
resource "aws_security_group_rule" "master_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.master_node.id
  description       = "Manager outbound (NAT, ECR, packages)"
}

# ── Worker(App) SG - Swarm 추가 규칙 ───────────

# 역할: Manager → Worker control plane 역방향 통신
# 용도: manager가 worker에 task 배포·상태 확인 시 사용
# 흐름: Manager → Worker:2377
resource "aws_security_group_rule" "app_ingress_swarm_management_from_master" {
  type                     = "ingress"
  from_port                = 2377
  to_port                  = 2377
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.master_node.id
  security_group_id        = aws_security_group.app.id
  description              = "Swarm cluster management from manager"
}

# 역할: Worker 간 control/gossip 보조 통신
# 용도: ASG로 scale-out된 worker끼리 Swarm 내부 통신
# 흐름: Worker → Worker:2377
resource "aws_security_group_rule" "app_ingress_swarm_management_self" {
  type                     = "ingress"
  from_port                = 2377
  to_port                  = 2377
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.app.id
  description              = "Swarm cluster management between workers"
}

# 역할: Manager → Worker Gossip (TCP)
# 흐름: Manager → Worker:7946
resource "aws_security_group_rule" "app_ingress_swarm_gossip_tcp_from_master" {
  type                     = "ingress"
  from_port                = 7946
  to_port                  = 7946
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.master_node.id
  security_group_id        = aws_security_group.app.id
  description              = "Swarm node discovery TCP from manager"
}

# 역할: Worker 간 Gossip (TCP)
# 흐름: Worker → Worker:7946
resource "aws_security_group_rule" "app_ingress_swarm_gossip_tcp_self" {
  type                     = "ingress"
  from_port                = 7946
  to_port                  = 7946
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.app.id
  description              = "Swarm node discovery TCP between workers"
}

# 역할: Manager → Worker Gossip (UDP)
# 흐름: Manager → Worker:7946
resource "aws_security_group_rule" "app_ingress_swarm_gossip_udp_from_master" {
  type                     = "ingress"
  from_port                = 7946
  to_port                  = 7946
  protocol                 = "udp"
  source_security_group_id = aws_security_group.master_node.id
  security_group_id        = aws_security_group.app.id
  description              = "Swarm node discovery UDP from manager"
}

# 역할: Worker 간 Gossip (UDP)
# 흐름: Worker → Worker:7946
resource "aws_security_group_rule" "app_ingress_swarm_gossip_udp_self" {
  type                     = "ingress"
  from_port                = 7946
  to_port                  = 7946
  protocol                 = "udp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.app.id
  description              = "Swarm node discovery UDP between workers"
}

# 역할: Manager → Worker Overlay (VXLAN)
# 흐름: Manager → Worker:4789
resource "aws_security_group_rule" "app_ingress_swarm_overlay_from_master" {
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  source_security_group_id = aws_security_group.master_node.id
  security_group_id        = aws_security_group.app.id
  description              = "Swarm overlay network from manager"
}

# 역할: Worker 간 Overlay (VXLAN) - multi-node 서비스 트래픽
# 흐름: Worker → Worker:4789
resource "aws_security_group_rule" "app_ingress_swarm_overlay_self" {
  type                     = "ingress"
  from_port                = 4789
  to_port                  = 4789
  protocol                 = "udp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.app.id
  description              = "Swarm overlay network between workers"
}

##############################
# 아래는 모니터링을 위한 보안규칙
##############################

# 내 pc > bastion grafana
resource "aws_security_group_rule" "bastion_ingress_grafana_from_my_ip" {
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion.id
  description       = "Public Grafana access"
}

# 내 pc > bastion prometheus
resource "aws_security_group_rule" "bastion_ingress_prometheus_from_my_ip" {
  type              = "ingress"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion.id
  description       = "Public Prometheus access"
}

# app alloy > bastion loki
resource "aws_security_group_rule" "bastion_ingress_loki_from_app" {
  type                     = "ingress"
  from_port                = 3100
  to_port                  = 3100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  security_group_id        = aws_security_group.bastion.id
  description              = "Alloy on app to Loki"
}

# bastion prometheus > app node exporter
resource "aws_security_group_rule" "app_ingress_node_exporter_from_bastion" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.app.id
  description              = "Prometheus to app node-exporter"
}

# bastion prometheus > db node exporter
resource "aws_security_group_rule" "db_ingress_node_exporter_from_bastion" {
  type                     = "ingress"
  from_port                = 9100
  to_port                  = 9100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.db.id
  description              = "Prometheus to db node-exporter"
}

# bastion prometheus > db cadvisor
resource "aws_security_group_rule" "db_ingress_cadvisor_from_bastion" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.db.id
  description              = "Prometheus to db cAdvisor"
}

# bastion prometheus > app cadvisor
resource "aws_security_group_rule" "app_ingress_cadvisor_from_bastion" {
  type                     = "ingress"
  from_port                = 8081
  to_port                  = 8081
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.app.id
  description              = "Prometheus to app cAdvisor"
}

resource "aws_security_group_rule" "master_ingress_redis_exporter_from_bastion" {
  type                     = "ingress"
  from_port                = 9121
  to_port                  = 9121
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.master_node.id
  description              = "Prometheus to Redis exporter"
}
