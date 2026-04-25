# Lab 02 — Recording Rules + Alert Rules

## 1. Recording Rule 적용

```bash
kubectl apply -f manifests/recording-rules.yaml
kubectl get prometheusrule -n monitoring
```

## 2. Prometheus 가 rule 등록 확인

http://localhost:9090/rules — 그룹 목록에 `order-msa.recording`, `order-msa.alerts`.

## 3. recorded metric 직접 쿼리

원래 비싼 쿼리:
```promql
histogram_quantile(0.99,
  sum by (le, namespace, service) (
    rate(gin_request_duration_seconds_bucket[5m])
  )
)
```

이제 단순 metric 으로:
```promql
namespace:http_latency_p99:seconds
```

→ **Grafana 대시보드는 recorded metric 을 사용** 해야 빠르고 가벼움.

## 4. Naming convention (Brian Brazil)

```
level:metric:operation

level         — 어느 차원에서 (namespace / pod / instance)
metric        — 무엇 (http_rps / cpu_utilization / latency)
operation     — 무엇을 했나 (sum / ratio / p99)
```

좋은 예:
- `namespace:http_rps:sum`
- `pod:cpu_utilization:ratio`
- `instance:node_cpu:rate1m`

나쁜 예:
- `my_rps` (level 불명)
- `total_requests` (operation 불명)

## 5. Alert rule 동작 확인

http://localhost:9090/alerts — 등록된 alert 들.

`HighErrorRate` 가 `Inactive` 면 정상 (에러율 5% 미만).

### 인위적으로 발생시키기

```bash
# order-service 의 새 요청에 의도적 에러 (예: 잘못된 JSON)
kubectl run -it --rm err-gen --image=alpine -n order -- sh -c "
  apk add -q curl &&
  for i in \$(seq 1 1000); do
    curl -sX POST http://order-service/orders -H 'Content-Type: application/json' -d 'INVALID' > /dev/null
  done"

# 5xx 가 안 나면 (앱이 400 만 응답해서) — 다른 부하 생성기 사용 또는 시뮬레이션
```

또는 메트릭 자체를 manual 로 push (Pushgateway 사용 예):
```bash
# Pushgateway 가 떠 있다면
echo "fake_5xx 1" | curl --data-binary @- http://pushgateway:9091/metrics/job/test
```

## 6. Alert 의 Pending → Firing → Resolved 라이프사이클

```
Pending  ─── 조건 만족 시작
   ↓
   for: 5m  유지
   ↓
Firing   ─── Alertmanager 로 통지
   ↓
   조건 해제 + resolve_timeout 후
   ↓
Resolved
```

`for: 5m` 의 의미: 5분 동안 expr 가 true 면 alert. 일시적 spike 무시.

## 7. 자주 쓰는 alert 패턴

### 7.1 Multi-window
```yaml
expr: |
  (
    namespace:http_error_rate:ratio > 0.05
    and
    namespace:http_error_rate:ratio offset 1h > 0.05
  )
```
→ 1시간 전부터 지속된 문제만 alert (false positive 줄임).

### 7.2 Burn-rate (SLO)
다음 모듈 23 에서 본격 다룸. 미리보기:
```yaml
- alert: ErrorBudgetBurning
  expr: |
    (
      sum(rate(http_requests_total{status=~"5.."}[1h])) / sum(rate(http_requests_total[1h])) > 0.05
      and
      sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 0.05
    )
  for: 2m
```

## 8. recording rule 의 비용 vs 이점

### 비용
- 추가 시계열 (record 마다 1개 — 차원에 따라 N개)
- 평가 주기마다 쿼리 실행 (CPU)

### 이점
- 대시보드 / alert 가 단순 lookup → 빠름
- 같은 비싼 쿼리를 30+ 패널이 쓴다면 큰 절감

→ 자주 쓰는 비싼 쿼리만 recording 권장.

## 학습 확인

1. recording rule 의 평가 주기 (`interval`) 가 너무 짧으면 어떤 부작용?
2. alert 의 `for` 와 recording rule 의 `interval` 의 관계는?
3. recording rule 의 `record` 이름이 잘못됐을 때 검증 방법?

다음: [quiz.md](./quiz.md)
