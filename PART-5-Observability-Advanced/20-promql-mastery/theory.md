# 이론 — PromQL Mastery

## 1. 4가지 메트릭 타입

### 1.1 Counter — 단조 증가

**의미**: 시작 후 누적량. 절대 안 줄어듦 (재시작 시 0 으로 리셋).

**예**:
```
http_requests_total
errors_total
bytes_sent_total
```

**naming 규칙**: `_total` suffix 권장.

**쿼리는 절대값이 아니라 rate**:
```promql
# 지난 1분간 RPS
rate(http_requests_total[1m])

# 지난 5분 RPS (smoother)
rate(http_requests_total[5m])

# 즉시 RPS (last 2 samples)
irate(http_requests_total[1m])
```

`rate` vs `irate`:
- rate: range 의 평균 (smooth)
- irate: 마지막 2 샘플의 차이 (즉각, 노이즈 ↑)

대시보드는 rate, alert 는 보통 rate (안정적).

### 1.2 Gauge — 임의로 오르내림

**의미**: 어느 순간의 값.

**예**:
```
goroutines_count
memory_bytes
queue_length
temperature_celsius
```

**쿼리는 그대로**:
```promql
# 현재 메모리
node_memory_MemAvailable_bytes

# 변화량 (rate 사용 X — 의미 없음)
delta(queue_length[5m])
```

### 1.3 Histogram — bucket 별 카운트

**의미**: 분포를 미리 정한 bucket 으로 누적. 서버 측에서 quantile 계산 가능.

**예** (latency):
```
http_request_duration_seconds_bucket{le="0.005"}  → ≤5ms 응답 수
http_request_duration_seconds_bucket{le="0.01"}   → ≤10ms 응답 수
http_request_duration_seconds_bucket{le="0.05"}   → ...
http_request_duration_seconds_bucket{le="+Inf"}   → 전체
http_request_duration_seconds_sum                 → 합산 시간
http_request_duration_seconds_count               → 호출 수
```

**쿼리** — p99 latency:
```promql
histogram_quantile(0.99,
  sum by (le, path) (rate(http_request_duration_seconds_bucket[5m]))
)
```

`sum by (le, path)` 가 핵심 — 여러 Pod 의 같은 path 의 bucket 을 합쳐서 quantile 계산.

**평균 latency**:
```promql
sum by (path) (rate(http_request_duration_seconds_sum[5m]))
  / sum by (path) (rate(http_request_duration_seconds_count[5m]))
```

### 1.4 Summary — quantile 직접 계산 (client 측)

**의미**: 클라이언트가 quantile (p50, p95, p99) 을 미리 계산.

**예**:
```
rpc_duration_seconds{quantile="0.5"}    → p50
rpc_duration_seconds{quantile="0.99"}   → p99
rpc_duration_seconds_sum
rpc_duration_seconds_count
```

**문제**: 여러 Pod 의 quantile 을 합산 못 함 (수학적으로). → 가능한 Histogram 권장.

## 2. 자주 쓰는 함수

### 2.1 시간 함수
- `rate(metric[5m])` — Counter 의 초당 평균 증가
- `irate(metric[1m])` — 즉시 변화율 (마지막 2 샘플)
- `increase(metric[1h])` — range 동안 총 증가
- `delta(metric[5m])` — Gauge 의 차이
- `deriv(metric[5m])` — Gauge 의 초당 변화율 (회귀)

### 2.2 집계
- `sum`, `avg`, `max`, `min`, `count`
- `sum by (label) (...)` — 라벨별 집계
- `sum without (label) (...)` — 그 라벨만 제외하고 집계

```promql
# Pod 별 CPU
sum by (pod) (rate(container_cpu_usage_seconds_total[1m]))

# 노드별 합산 (pod 라벨 제거)
sum without (pod) (rate(container_cpu_usage_seconds_total[1m]))
```

### 2.3 vector matching
```promql
# CPU usage / CPU limit 비율
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="order"}[1m]))
  /
sum by (pod) (kube_pod_container_resource_limits{namespace="order",resource="cpu"})
```

label set 이 양쪽에서 매칭되어야. 안 맞으면 `on()` / `ignoring()` / `group_left` / `group_right` 사용.

### 2.4 topk / bottomk
```promql
topk(5, sum by (pod) (rate(http_requests_total[1m])))
```

## 3. RED 메트릭 패턴 (서비스 레벨)

**R**ate, **E**rrors, **D**uration:
```promql
# Rate
sum by (service) (rate(http_requests_total[1m]))

# Errors
sum by (service) (rate(http_requests_total{status=~"5.."}[1m]))
  / sum by (service) (rate(http_requests_total[1m]))

# Duration (p99)
histogram_quantile(0.99, sum by (le, service) (rate(http_request_duration_seconds_bucket[5m])))
```

## 4. USE 패턴 (자원 레벨)

**U**tilization, **S**aturation, **E**rrors:
- CPU utilization: `rate(node_cpu_seconds_total{mode!="idle"}[1m])`
- Memory utilization: `1 - (node_memory_MemAvailable / node_memory_MemTotal)`
- Disk saturation: `rate(node_disk_io_time_weighted_seconds_total[1m])`
- Network errors: `rate(node_network_receive_errs_total[1m])`

## 5. Recording Rules — 비싼 쿼리 사전 계산

자주 쓰는 비싼 쿼리를 주기적으로 미리 계산 → 새 metric 으로 저장:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  labels:
    release: kps
spec:
  groups:
    - name: recording.rules
      interval: 30s
      rules:
        - record: namespace:http_requests_per_second:sum
          expr: sum by (namespace) (rate(http_requests_total[1m]))

        - record: namespace:http_error_rate:ratio
          expr: |
            sum by (namespace) (rate(http_requests_total{status=~"5.."}[1m]))
              /
            sum by (namespace) (rate(http_requests_total[1m]))
```

**Naming convention**: `level:metric:operation` (Brian Brazil 규칙).

## 6. Alert Rules

```yaml
groups:
  - name: app.alerts
    rules:
      - alert: HighErrorRate
        expr: namespace:http_error_rate:ratio > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "{{ $labels.namespace }} error rate {{ $value | humanizePercentage }}"
```

`for: 5m` — 5분 동안 조건 유지되어야 alert. 일시적 spike 무시.

## 7. PromQL 안티패턴

| 패턴 | 문제 | 대안 |
|------|------|------|
| `rate(gauge[5m])` | Gauge 에 rate 의미 없음 | `delta` / `deriv` |
| `histogram_quantile(0.99, http_request_duration_seconds_bucket)` | rate 안 감싸 | `histogram_quantile(0.99, sum by(le)(rate(... [5m])))` |
| `sum(rate(...))` 라벨 없이 | 모든 라벨 합쳐 의미 상실 | `sum by (path)` 또는 `sum by (instance)` 등 |
| `avg(quantile)` (Summary) | 수학적 잘못 | Histogram 으로 마이그 |

다음: [lab-01-query-patterns.md](./lab-01-query-patterns.md)
