# Lab 01 — Scrape 동작 직접 분석

## 1. Prometheus 의 targets 페이지

```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
```

브라우저: http://localhost:9090/targets

각 target 의 정보:
- **State** — UP / DOWN
- **Endpoint** — `http://10.20.x.y:9090/metrics`
- **Last Scrape** — 마지막 scrape 시각
- **Scrape Duration** — 응답 시간
- **Labels** — 자동 부여된 라벨 (job, instance, pod, namespace 등)

## 2. CLI 로 target 정보

```bash
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[0]'
```

기대 (예시):
```json
{
  "discoveredLabels": {
    "__address__": "10.20.1.5:9090",
    "__meta_kubernetes_pod_name": "order-service-xxx",
    "__meta_kubernetes_namespace": "order"
  },
  "labels": {
    "namespace": "order",
    "pod": "order-service-xxx",
    "job": "order-msa"
  },
  "scrapePool": "serviceMonitor/monitoring/order-msa/0",
  "scrapeUrl": "http://10.20.1.5:9090/metrics",
  "lastScrape": "...",
  "lastScrapeDuration": 0.012,
  "health": "up"
}
```

`discoveredLabels` (`__meta_*`) 는 SD 결과 → relabel 후 `labels` 만 남음.

## 3. /metrics 직접 호출

```bash
kubectl run -it --rm dbg --image=alpine -n order -- sh -c "
  apk add -q curl
  curl -s http://order-service:9090/metrics | head -30
"
```

기대:
```
# HELP go_goroutines Number of goroutines
# TYPE go_goroutines gauge
go_goroutines 8

# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{code="200",method="POST",path="/orders"} 12345
...
```

각 메트릭은 `# HELP` + `# TYPE` 헤더 + 샘플(들).

## 4. 한 메트릭의 시계열 수

```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=count by (__name__)({__name__="http_requests_total"})' \
  | jq '.data.result[0].value[1]'
```

→ 그 메트릭 이름의 라벨 조합 수 = 시계열 수.

## 5. 전체 시계열 수

```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=count({__name__=~".+"})' \
  | jq -r '.data.result[0].value[1]'
```

학습 클러스터면 보통 5,000 ~ 50,000.

## 6. TSDB 상태 (Prometheus UI)

http://localhost:9090/tsdb-status

표시되는 정보:
- Number of series
- Top label names by series count
- Top metric names by series count
- Memory chunks 등

## 7. ServiceMonitor 의 selector 매칭 디버그

```bash
# Prometheus 의 selector 확인
kubectl get prometheus -n monitoring -o yaml | yq '.items[].spec.serviceMonitorSelector'

# 내 ServiceMonitor 의 라벨
kubectl get servicemonitor -n monitoring order-msa -o yaml | yq '.metadata.labels'
```

매칭 안 되면 `release: kps` 라벨 추가.

## 8. scrape interval / timeout 변경

ServiceMonitor:
```yaml
endpoints:
  - port: metrics
    interval: 15s
    scrapeTimeout: 10s     # interval 보다 짧아야
```

너무 짧으면 — Prometheus 부하 ↑, 너무 길면 — 일시 spike 놓침.

## 학습 확인

1. `__meta_*` 라벨이 최종 메트릭에 안 남는 이유는?
2. 같은 Pod 의 metrics endpoint 가 여러 개라면 어떻게 노출?
3. scrape_timeout > interval 이면 어떤 일이?

다음: [lab-02-cardinality.md](./lab-02-cardinality.md)
