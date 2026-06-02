#!/bin/bash
set -e

apt-get update -y
apt-get install -y nginx awscli

# IMDSv2로 인스턴스 메타데이터 조회
TOKEN=$(curl -sf -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)
REGION=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region)

# AZ 마지막 문자 (a 또는 c), 인스턴스 ID 앞 8자리
AZ_SUFFIX=$(echo "$AZ" | rev | cut -c1)
SHORT_ID=$(echo "$INSTANCE_ID" | sed 's/i-//' | cut -c1-8)

# 인스턴스 Name 태그 자동 설정: prod-ict-app-a-0abc1234
aws ec2 create-tags \
  --region "$REGION" \
  --resources "$INSTANCE_ID" \
  --tags "Key=Name,Value=${name_prefix}-app-$AZ_SUFFIX-$SHORT_ID" || true

systemctl enable nginx
systemctl start nginx

echo "OK - ALB Health Check Success" > /var/www/html/index.html
echo "healthy" > /var/www/html/health

systemctl restart nginx
