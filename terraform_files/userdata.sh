#!/bin/bash
set -e

apt update -y
apt install -y nginx

systemctl enable nginx
systemctl start nginx

echo "OK - ALB Health Check Success" > /var/www/html/index.html
echo "healthy" > /var/www/html/health

systemctl restart nginx