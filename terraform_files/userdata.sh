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
apt-get install -y docker-ce docker-ce-cli containerd.io

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

mkdir -p /opt/nginx-test

cat > /opt/nginx-test/index.html <<EOF
<!doctype html>
<html lang="ko">
  <head>
    <meta charset="utf-8">
    <title>ICT Studio ALB Test</title>
    <style>
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        font-family: Arial, "Noto Sans KR", sans-serif;
        background: #f4f7fb;
        color: #1f2937;
      }
      main {
        width: min(720px, calc(100% - 40px));
        padding: 32px;
        border: 1px solid #d8dee8;
        border-radius: 8px;
        background: #ffffff;
        box-shadow: 0 12px 32px rgba(15, 23, 42, 0.08);
      }
      h1 {
        margin: 0 0 20px;
        font-size: 32px;
      }
      p {
        margin: 10px 0;
        font-size: 18px;
        line-height: 1.6;
      }
      strong {
        color: #0f766e;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>ICT Studio ALB Test</h1>
      <p>여기는 Private <strong>$PRIVATE_IP</strong> 서버입니다.</p>
      <p>Instance ID: <strong>$INSTANCE_ID</strong></p>
      <p>Availability Zone: <strong>$AZ</strong></p>
      <p>ALB routing test success</p>
    </main>
  </body>
</html>
EOF

echo "ok" > /opt/nginx-test/health

docker rm -f nginx-test || true
docker run -d \
  --name nginx-test \
  --restart always \
  -p 80:80 \
  -v /opt/nginx-test:/usr/share/nginx/html:ro \
  nginx:latest
