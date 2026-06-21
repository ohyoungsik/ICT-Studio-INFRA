#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

# Terraform output을 읽어 Ansible inventory JSON으로 변환한다.
# terraform apply 이후에만 PostgreSQL HA private IP output이 채워진다.
ROOT = Path(__file__).resolve().parents[2]
TF_DIR = ROOT / "terraform_files"


def terraform_output():
    # terraform output -json 실패 시 apply 전 상태로 보고 빈 inventory를 반환한다.
    try:
        raw = subprocess.check_output(
            ["terraform", "-chdir=" + str(TF_DIR), "output", "-json"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        print(json.dumps(
            {
                "_meta": {"hostvars": {}},
                "postgres_primary": {"hosts": []},
                "postgres_replicas": {"hosts": []},
                "postgres_db_nodes": {"hosts": []},
                "postgres_swarm_manager": {"hosts": []},
                "postgres_swarm_workers": {"hosts": []},
                "postgres_ha": {"hosts": []},
                "monitoring_server": {"hosts": []},
            }
        ))
        return None
    return json.loads(raw)


def value(outputs, name, default=None):
    item = outputs.get(name)
    if isinstance(item, dict) and "value" in item:
        return item["value"]
    return default


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--host":
        print(json.dumps({}))
        return

    outputs = terraform_output()
    if outputs is None:
        return

    # Terraform이 생성한 pem 파일명과 Bastion public IP를 output에서 읽는다.
    key_name = value(outputs, "key_pair_name", "ict-project-key")
    key_path = TF_DIR / f"{key_name}.pem"
    bastion_public_ip = value(outputs, "bastion_public_ip", "")

    # DB subnet의 모든 PostgreSQL HA 관련 노드는 private IP를 ansible_host로 사용한다.
    hosts = {
        "bastion": value(outputs, "bastion_public_ip"),
        "db-main": value(outputs, "db_main_private_ip"),
        "postgres-primary": value(outputs, "postgres_primary_private_ip"),
        "postgres-replica1": value(outputs, "postgres_replica1_private_ip"),
        "postgres-replica2": value(outputs, "postgres_replica2_private_ip"),
    }

    proxy = ""
    # Ansible은 Bastion을 ProxyCommand로 경유해 DB private IP에 SSH 접속한다.
    # ProxyJump는 jump host SSH에 identity file이 명확히 전달되지 않는 환경이 있어,
    # Bastion 접속에도 같은 pem key를 직접 지정하는 ProxyCommand를 사용한다.
    if bastion_public_ip:
        proxy = (
            "-o StrictHostKeyChecking=no "
            "-o UserKnownHostsFile=/dev/null "
            "-o 'ProxyCommand=ssh -i {key} -o StrictHostKeyChecking=no "
            "-o UserKnownHostsFile=/dev/null -W %h:%p ubuntu@{bastion}'"
        ).format(key=key_path, bastion=bastion_public_ip)

    hostvars = {}
    for host, private_ip in hosts.items():
        if not private_ip:
            continue
        hostvars[host] = {
            "ansible_host": private_ip,
            "ansible_user": "ubuntu",
            "ansible_ssh_private_key_file": str(key_path),
        }
        if host != "bastion" and proxy:
            hostvars[host]["ansible_ssh_common_args"] = proxy

    # db-main은 Swarm manager와 HAProxy 노드이다.
    # postgres-primary, postgres-replica1, postgres-replica2는 PostgreSQL 데이터 service 배치 노드이다.
    inventory = {
        "postgres_primary": {"hosts": ["postgres-primary"] if "postgres-primary" in hostvars else []},
        "postgres_replicas": {"hosts": [h for h in ["postgres-replica1", "postgres-replica2"] if h in hostvars]},
        "postgres_db_nodes": {"hosts": [h for h in ["postgres-primary", "postgres-replica1", "postgres-replica2"] if h in hostvars]},
        "postgres_swarm_manager": {"hosts": ["db-main"] if "db-main" in hostvars else []},
        "postgres_swarm_workers": {"hosts": [h for h in ["postgres-primary", "postgres-replica1", "postgres-replica2"] if h in hostvars]},
        "postgres_ha": {
            "hosts": [h for h in ["db-main", "postgres-primary", "postgres-replica1", "postgres-replica2"] if h in hostvars]
        },
        "monitoring_server": {"hosts": ["bastion"] if "bastion" in hostvars else []},
        "_meta": {"hostvars": hostvars},
    }
    print(json.dumps(inventory, indent=2))


if __name__ == "__main__":
    main()
