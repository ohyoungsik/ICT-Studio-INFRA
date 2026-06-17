# Redis 큐 길이 기반 Auto Scaling 검증 정리

## 목표

Redis 대기열 길이를 기준으로 Auto Scaling Group이 scale-out 되는 구조를 구축하고 검증한다.

기존 CPU 기반 오토스케일링은 `stress` 테스트로 동작을 확인했다.  
이번 검증의 목적은 k6 요청 증가로 Redis 큐 길이가 늘어났을 때 app 서버가 자동 확장되는지 확인하는 것이다.

## 현재 인프라 구조

```text
User / k6
  -> ALB
  -> Auto Scaling Group
  -> FastAPI app server
  -> Redis
```

주요 리소스:

```text
ALB: prod-ict-alb
ASG: prod-ict-app-asg
Backend target group: prod-ict-backend-tg
Redis 위치: prod-ict-master-node
```

## Redis 대기열 구조

Redis는 master node에서 Docker 컨테이너로 실행된다.

```text
prod-ict-master-node
  -> redis container
```

백엔드 대기열은 Redis sorted set 사용을 기준으로 한다.

```redis
ZADD queue:concert:1:zset <score> <userId>
ZCARD queue:concert:1:zset
ZRANK queue:concert:1:zset <userId>
```

인프라 publisher는 아래 key를 우선 조회한다.

```text
queue:concert:1:zset
```

마이그레이션 기간에는 기존 list key도 fallback으로 조회한다.

```text
queue:concert:1
```

fallback 조회:

```redis
LLEN queue:concert:1
```

## 큐 길이 Metric 발행

master node에는 SSM Association으로 `queue-metric-publisher`가 설치된다.

publisher 동작:

```text
30초마다 실행
-> Redis 큐 길이 조회
-> 현재 ASG InService 인스턴스 수 조회
-> QueueLengthPerInstance 계산
-> CloudWatch custom metric 발행
```

CloudWatch namespace:

```text
ICT/Queue
```

발행 metric:

```text
QueueLength
QueueLengthPerInstance
QueueLengthPerInstanceForAsg
```

ASG target tracking policy는 아래 metric을 사용한다.

```text
MetricName: QueueLengthPerInstanceForAsg
Target: 3000
```

## Auto Scaling 정책

현재 ASG에는 두 가지 scaling policy가 있다.

```text
1. CPU 기반
   Metric: ASGAverageCPUUtilization
   Target: 70%

2. Redis 큐 길이 기반
   Metric: QueueLengthPerInstanceForAsg
   Target: 3000
```

큐 기반 scale-out 기대 흐름:

```text
k6 요청 증가
-> /api/queue/join 호출
-> Redis queue length 증가
-> QueueLengthPerInstanceForAsg 증가
-> ASG desired capacity 증가
-> 새 app instance InService
```

## 부하 테스트

백엔드 k6 스크립트는 백엔드 저장소에서 관리한다.

[ohyoungsik/ICT-Studio-BE](https://github.com/ohyoungsik/ICT-Studio-BE)

실행 예시:

```powershell
k6 run --vus 500 --duration 3m `
  -e BASE_URL=http://prod-ict-alb-469671516.ap-northeast-2.elb.amazonaws.com `
  .\k6\ticketing-load-test.js
```

대기열 초과 정책에서는 `429 Too Many Requests`가 정상 응답일 수 있다.

따라서 k6 결과는 아래 항목을 함께 본다.

```text
checks
server_errors
status code distribution
http_req_duration
```

`http_req_failed`는 429를 실패로 집계할 수 있으므로, 대기열 초과 테스트에서는 단독 기준으로 보지 않는다.

## 확인 명령

### Redis 큐 길이 확인

master node에서 확인:

```bash
docker exec redis redis-cli -a "$REDIS_PASSWORD" ZCARD queue:concert:1:zset
```

fallback list 확인:

```bash
docker exec redis redis-cli -a "$REDIS_PASSWORD" LLEN queue:concert:1
```

### CloudWatch metric 확인

```powershell
aws cloudwatch get-metric-statistics `
  --namespace ICT/Queue `
  --metric-name QueueLengthPerInstanceForAsg `
  --statistics Average `
  --period 60 `
  --start-time 2026-06-17T08:20:00Z `
  --end-time 2026-06-17T08:50:00Z `
  --region ap-northeast-2
```

`Datapoints`가 비어 있으면 ASG가 큐 길이를 볼 수 없으므로 scale-out이 발생하지 않는다.

### Queue metric publisher 확인

master node에서 확인:

```bash
systemctl status queue-metric-publisher.timer
systemctl status queue-metric-publisher.service
journalctl -u queue-metric-publisher.service -n 100 --no-pager
```

정상 로그 예시:

```text
Published queue metrics length=10000 in_service=1 per_instance=10000.00
```

### ASG 정책 확인

```powershell
aws autoscaling describe-policies `
  --auto-scaling-group-name prod-ict-app-asg `
  --region ap-northeast-2
```

확인해야 할 정책:

```text
prod-ict-cpu-target
prod-ict-queue-target
```

### Scale-Out activity 확인

```powershell
aws autoscaling describe-scaling-activities `
  --auto-scaling-group-name prod-ict-app-asg `
  --region ap-northeast-2 `
  --max-items 10
```

진짜 scale-out은 desired capacity가 증가해야 한다.

예상되는 흐름:

```text
DesiredCapacity 1
-> DesiredCapacity 2
-> DesiredCapacity 3
-> DesiredCapacity 4
```

아래 원인은 scale-out 성공이 아니라 교체 작업이다.

```text
Cause: instance refresh
Cause: ELB system health check failure
Cause: unhealthy instance needing to be replaced
```

## 현재까지 확인한 내용

```text
CPU stress 기반 scale-out: 확인 완료
k6 요청 기반 Redis 병목: 확인 완료
Redis LRANGE 전체 조회 병목: 확인 완료
429 기반 빠른 거절 후 응답시간 개선: 확인 완료
QueueLengthPerInstanceForAsg metric publisher: 구성 완료
SSM publisher 설치 스크립트 오류: 수정 완료
QueueLengthPerInstanceForAsg metric Datapoints: 재확인 필요
k6 기반 queue length scale-out: 재검증 필요
```

## 향후 계획

현재 백엔드는 `/api/queue/process`와 `/api/queue/worker`를 제공한다.
두 API는 Redis sorted set에서 `ZPOPMIN`으로 대기열을 소비한다.

인프라에서는 scale-in 검증을 위해 선택형 queue consumer를 제공한다.

```text
enable_queue_consumer = false
```

기본값은 `false`이다. 테스트 중 scale-in 검증이 필요할 때만 `true`로 켠다.

consumer 동작:

```text
master node systemd timer
-> ALB 경유로 /api/queue/worker 호출
-> Redis queue length 감소
-> QueueLengthPerInstanceForAsg 감소
-> ASG scale-in 평가
```

관련 Terraform 변수:

```text
enable_queue_consumer
queue_consumer_batch_size
queue_consumer_interval_seconds
```

예상 Redis 명령:

```redis
ZPOPMIN queue:concert:1:zset
```

또는:

```redis
ZREM queue:concert:1:zset <userId>
```

이를 통해 scale-in까지 검증한다.

```text
Queue Length 감소
-> QueueLengthPerInstanceForAsg 감소
-> ASG scale-in
```

주의:

```text
consumer를 너무 빨리 돌리면 queue length가 scale-out target까지 올라가기 전에 감소할 수 있다.
scale-out 검증 단계에서는 consumer를 끄고,
scale-in 검증 단계에서만 consumer를 켜는 것을 권장한다.
```

## 결론

우리 프로젝트에서 k6 요청만으로 CPU 기반 오토스케일링을 확인하기는 어렵다.

대기열 초과 요청은 429로 빠르게 반환되므로 CPU가 크게 증가하지 않는다.  
따라서 Redis queue length를 CloudWatch custom metric으로 발행하고, ASG가 해당 metric을 기준으로 확장되도록 구성했다.

최종 검증은 아래 순서로 진행한다.

```text
1. publisher가 CloudWatch metric을 발행하는지 확인
2. QueueLengthPerInstanceForAsg가 3000 이상으로 올라가는지 확인
3. prod-ict-queue-target 정책으로 desired capacity가 증가하는지 확인
4. 새 app instance가 InService가 되는지 확인
```
