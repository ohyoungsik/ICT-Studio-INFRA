#!/usr/bin/env bash
set -euo pipefail

hostnamectl set-hostname "${hostname}"

cat >/etc/hosts.tmp <<EOF
127.0.0.1 localhost
127.0.1.1 ${hostname}
EOF

grep -vE '^(127\.0\.0\.1|127\.0\.1\.1)\s' /etc/hosts >>/etc/hosts.tmp || true
mv /etc/hosts.tmp /etc/hosts

mkdir -p /data/postgres
chown -R 1001:1001 /data/postgres
chmod 700 /data/postgres
