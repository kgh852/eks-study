# Lab 02 — Cardinality 폭발 시연 + 진단

## 학습 확인 포인트

- [ ] cardinality 가 어떻게 폭증하는지 직접 봄
- [ ] Prometheus 의 cardinality 분석 도구 사용
- [ ] metric_relabel 로 라벨 drop 해서 줄이기

## 1. Top cardinality 확인 (베이스라인)

```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=topk(10, count by (__name__)({__name__=~".+"}))' \
  | jq -r '.data.result[] | "\(.metric.__name__)\t\(.value[1])"' \
  | sort -k2 -nr
```

기대 (예시):
```
apiserver_request_duration_seconds_bucket    8500   ← histogram 의 bucket 별
container_network_receive_bytes_total        2400
kubelet_runtime_operations_duration_seconds_bucket  2000
...
```

## 2. 라벨 카운트

```bash
curl -sG http://localhost:9090/api/v1/labels | jq '.data | length'
```

→ 클러스터 전체에서 사용되는 라벨 종류 수.

## 3. 의도적 cardinality 폭발

라벨 값에 timestamp 같은 고유 값 넣으면 시계열 폭증:

```bash
# Counter 메트릭에 user_id 라벨을 1만 개 다른 값으로
kubectl run cardinality-bomb -n order --image=alpine --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"c","image":"alpine","command":["sh","-c"],"args":["apk add -q curl && for i in $(seq 1 5000); do curl -s -X POST http://order-service/orders -H Content-Type:application/json -d {\"user_id\":\"u-'$i'\",\"amount\":1} > /dev/null; done; sleep 600"]}]}}'
```

15분 정도 두면 order-service 가 user_id 별로 메트릭을 노출 (만약 `user_id` 가 라벨에 들어간다면 — 본 lab 의 order-service 는 이미 적절히 짜여 있어서 user_id 를 라벨로 안 씀. 이건 가상 시나리오 시뮬레이션.).

**더 직접적인 시뮬레이션** — Prometheus 가 내부에 만든 라벨 폭주 측정:

```bash
# 모든 Pod가 만들어내는 시계열 수 추이
curl -sG http://localhost:9090/api/v1/query --data-urlencode 'query=prometheus_tsdb_head_series'
```

## 4. cardinality 진단 명령

### 4.1 메트릭 별 시계열 수
```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=topk(15, count by (__name__)({__name__=~".+"}))' \
  | jq -r '.data.result[] | "\(.value[1])\t\(.metric.__name__)"' | sort -k1 -nr
```

### 4.2 라벨 별 unique value 수
```bash
for label in pod namespace container job instance method status code; do
  COUNT=$(curl -sG http://localhost:9090/api/v1/label/${label}/values \
    | jq '.data | length')
  echo "$label: $COUNT"
done
```

### 4.3 특정 메트릭의 라벨 조합 분포
```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=count by (pod)({__name__="container_cpu_usage_seconds_total",namespace="order"})'
```

## 5. metric_relabel 로 cardinality 절감

ServiceMonitor 에 relabel 추가:
```yaml
spec:
  endpoints:
    - port: metrics
      metricRelabelings:
        # go_gc_* 시리즈 모두 drop
        - sourceLabels: [__name__]
          regex: 'go_gc_.+'
          action: drop

        # 특정 라벨 제거
        - regex: 'pod_template_hash'
          action: labeldrop
```

## 6. /api/v1/admin/tsdb/delete (위험 — 학습용만)

특정 시계열 영구 삭제 (--web.enable-admin-api 필요):
```bash
# 활성화 옵션이면:
curl -X POST 'http://localhost:9090/api/v1/admin/tsdb/delete_series?match[]=high_cardinality_metric'
```

→ 기본 비활성. 학습 환경에서 특정 시리즈가 디스크 잡아먹으면 사용 가능. 운영은 신중.

## 7. 정리

```bash
kubectl delete pod -n order cardinality-bomb --ignore-not-found
```

## 학습 확인

1. cardinality 가 메모리/디스크에 미치는 정확한 영향은?
2. 라벨에 user_id 넣으면 안 되는 이유는?
3. histogram 의 `le` 라벨이 cardinality 에 미치는 영향은?

다음: [lab-03-federation.md](./lab-03-federation.md)
