# Lab 01 — 자주 쓰는 PromQL 패턴

## 1. RED — 서비스 레벨 (order-service 사용)

### 1.1 Rate (RPS)
```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
```

http://localhost:9090 에서:
```promql
# 클러스터 전체 HTTP RPS
sum(rate(gin_request_duration_seconds_count[1m]))

# 서비스 별
sum by (service) (rate(gin_request_duration_seconds_count[1m]))
```

### 1.2 Errors
```promql
# 5xx 비율
sum by (service) (rate(gin_request_duration_seconds_count{code=~"5.."}[1m]))
  /
sum by (service) (rate(gin_request_duration_seconds_count[1m]))
```

### 1.3 Duration (Histogram p99)
```promql
histogram_quantile(0.99,
  sum by (le, path) (rate(gin_request_duration_seconds_bucket[5m]))
)
```

> Module 21 에서 Go 앱에 직접 메트릭을 추가하면 위 메트릭들이 실제로 채워집니다. 본 lab 에서는 메트릭 이름이 환경마다 다를 수 있어 가짜 데이터로 시연 가능.

## 2. USE — 자원 레벨

### 2.1 CPU
```promql
# 노드 CPU 사용률 (%)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)

# 컨테이너 CPU
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="order"}[1m]))
```

### 2.2 Memory
```promql
# 노드 메모리 사용률
1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

# 컨테이너 메모리
sum by (pod) (container_memory_working_set_bytes{namespace="order"})
```

### 2.3 Network
```promql
# Pod 별 수신 bytes/s
sum by (pod) (rate(container_network_receive_bytes_total{namespace="order"}[1m]))
```

## 3. 자주 쓰는 추가 패턴

### 3.1 Pod 재시작 횟수
```promql
sum by (namespace, pod) (kube_pod_container_status_restarts_total)
```

### 3.2 Top N (가장 비싼 5개)
```promql
topk(5, sum by (pod) (rate(container_cpu_usage_seconds_total[1m])))
```

### 3.3 노드별 Pod 수
```promql
count by (node) (kube_pod_info)
```

### 3.4 Container resource utilization
```promql
# CPU usage / requests
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="order"}[1m]))
  /
sum by (pod) (kube_pod_container_resource_requests{namespace="order",resource="cpu"})
```

이 비율이 0.5 미만이면 over-provisioning → Module 17 의 right-sizing.

## 4. Vector Matching 시연

```promql
# 두 메트릭이 다른 라벨 set 일 때
sum by (pod) (rate(container_cpu_usage_seconds_total[1m]))
  / on(pod)
sum by (pod) (kube_pod_container_resource_limits{resource="cpu"})
```

라벨 set 이 정확히 같으면 자동 매칭. 안 맞으면:
- `on(label1, label2)` — 명시 매칭
- `ignoring(label)` — 그 라벨 무시
- `group_left` / `group_right` — many-to-one

## 5. subquery 시연

```promql
# 지난 1시간 동안의 RPS 의 max
max_over_time(
  sum(rate(gin_request_duration_seconds_count[1m]))[1h:1m]
)
```

`[1h:1m]` — 1분 step 으로 1시간 평가.

## 6. 안티패턴 시연

다음 쿼리들이 왜 잘못됐는지 직접 실행해 결과 확인:

### 6.1 Counter 에 rate 안 감기
```promql
http_requests_total
```
→ 누적값. 시각화 의미 없음.

### 6.2 Histogram bucket 에 rate 안 감기
```promql
histogram_quantile(0.99, gin_request_duration_seconds_bucket)
```
→ 누적이라 quantile 결과가 누적 잡음. rate 필수.

### 6.3 sum 에 by 누락
```promql
sum(rate(gin_request_duration_seconds_count[1m]))
```
→ 모든 라벨 합쳐져 단일 값. 어느 서비스 / Pod 인지 모름.

올바른 쿼리:
```promql
sum by (service) (rate(gin_request_duration_seconds_count[1m]))
```

## 학습 확인

1. `rate(gauge[5m])` 가 의미 없는 이유?
2. Histogram 의 `le` 라벨이 cardinality 에 미치는 영향?
3. Summary 메트릭의 한계 (분산 환경에서)?

다음: [lab-02-recording-rules.md](./lab-02-recording-rules.md)
