## k6 세팅
```bash
# GPG 키 추가
sudo gpg -k

curl -fsSL https://dl.k6.io/key.gpg | \
sudo gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg

# 저장소 추가
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
sudo tee /etc/apt/sources.list.d/k6.list

# 패키지 목록 갱신
sudo apt-get update

# k6 설치
sudo apt-get install -y k6


```

## 오토스케일링 확인 방법
```bash
# 부하테스트 진행
K6_WEB_DASHBOARD=true k6 run script.js

# ASG 인스턴스 수 변화
aws autoscaling describe-auto-scaling-groups \
  --region ap-northeast-2 \
  --auto-scaling-group-names prod-ict-app-asg \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Instances:Instances|length(@)}'

# 스케일링 활동 로그
aws autoscaling describe-scaling-activities \
  --region ap-northeast-2 \
  --auto-scaling-group-name prod-ict-app-asg \
  --max-records 5
```