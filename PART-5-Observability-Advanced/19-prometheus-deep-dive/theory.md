# 이론 — Prometheus 아키텍처

## 1. Pull vs Push

Prometheus 는 **pull-based**:
- Prometheus 가 정기적으로 (`scrape_interval`) target 의 `/metrics` 호출
- target 은 그저 메트릭을 노출만 — 능동적으로 push 안 함

**장점**:
- target 자체가 단순 (HTTP 핸들러 1개)
- 죽은 target 자동 감지 (`up=0`)
- target 발견을 Service Discovery 가 담당

**단점**:
- 단명 batch job 메트릭 어려움 → Pushgateway 사용
- 외부망 target 어려움 → SSH tunnel / 프록시

## 2. 핵심 컴포넌트

```
┌──── Prometheus Server ────────────────┐
│   ┌────────────────┐                  │
│   │ Service        │  ← K8s API watch │
│   │ Discovery      │                  │
│   └─────┬──────────┘                  │
│         ▼                             │
│   ┌────────────────┐                  │
│   │ Scraper        │ HTTP GET /metrics│
│   └─────┬──────────┘                  │
│         ▼                             │
│   ┌────────────────┐                  │
│   │ TSDB (local)   │ disk: WAL + chunks│
│   └─────┬──────────┘                  │
│         ▼                             │
│   ┌────────────────┐                  │
│   │ Query engine   │ ← PromQL         │
│   │ (PromQL)       │                  │
│   └────────────────┘                  │
│         ▼                             │
│   ┌────────────────┐                  │
│   │ Rules / Alerts │ → Alertmanager   │
│   └────────────────┘                  │
└───────────────────────────────────────┘
```

## 3. TSDB (Time Series Database) 구조

### 3.1 한 개의 시계열 (time series) =

```
metric_name{label1=v1, label2=v2, ...}  →  [(t1, v1), (t2, v2), ...]
                                             ─── samples ───
```

**예**:
```
http_requests_total{method="GET", path="/api", status="200", pod="x-1"}
   →  (1700000000, 100), (1700000015, 105), (1700000030, 110), ...
```

### 3.2 라벨 조합 = 시계열 1개

같은 metric name 이라도 라벨 값이 다르면 다른 시계열:
- `http_requests_total{method="GET", status="200"}` — 시계열 A
- `http_requests_total{method="GET", status="500"}` — 시계열 B

→ **라벨이 N차원 카르테시안 곱**.

### 3.3 디스크 구조

```
data/
├── wal/                  # Write-Ahead Log (최근 ~2h)
├── 01HXXXX/              # 2h chunk
│   ├── meta.json
│   ├── chunks/000001
│   ├── index            # 라벨 → 시계열 인덱스
│   └── tombstones
├── 01HYYYY/
└── ...
```

기본 `--storage.tsdb.retention.time=15d` (학습 환경에선 1d로 줄임).

## 4. Cardinality — 메모리 / 디스크의 핵심 변수

**Cardinality = 시계열 수**

라벨 조합이 늘어날수록 시계열 수 폭발:
- `pod` 라벨 (Pod 100개) × `status` (5개) × `method` (4개) = 2,000 시계열 / 메트릭

```
시계열 수 ≈ 메트릭 수 × ∏(라벨 unique 값 수)
```

### 위험 패턴
- 라벨에 **user_id**, **request_id**, **timestamp** 같은 고유 값 사용 → 무한 cardinality
- 한 메트릭이 1만+ 시계열이면 점검 대상

### 측정
Prometheus UI → Status → TSDB Status:
- Top 10 label names with most series
- Top 10 series count by metric

PromQL:
```
topk(10, count by (__name__) ({__name__=~".+"}))
```

## 5. Service Discovery 메커니즘 (K8s)

Prometheus 는 K8s API 를 watch 해서 target 자동 발견.

옛날 방식 — `prometheus.yml` 에 `kubernetes_sd_configs`:
```yaml
- job_name: pods
  kubernetes_sd_configs:
    - role: pod
  relabel_configs:
    - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
      action: keep
      regex: true
```

→ Pod의 `prometheus.io/scrape: "true"` annotation 으로 등록.

**Prometheus Operator 방식 (kube-prometheus-stack)**: 위를 CRD 로 추상화.

## 6. ServiceMonitor / PodMonitor / Probe

### 6.1 ServiceMonitor (가장 흔함)
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    release: kps     # ← Prometheus 의 selector
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 15s
      path: /metrics
```

→ 매칭되는 Service 의 endpoints 에서 자동 scrape.

### 6.2 PodMonitor
Service 없이 Pod 직접:
```yaml
spec:
  selector:
    matchLabels: {app: worker}
  podMetricsEndpoints:
    - port: metrics
```

→ Headless Service / 외부 노출 불필요한 워크로드.

### 6.3 Probe (Blackbox)
외부 endpoint 의 health (HTTP/ICMP) 측정:
```yaml
spec:
  prober:
    url: blackbox-exporter:9115
  module: http_2xx
  targets:
    staticConfig:
      static:
        - https://api.example.com
```

## 7. relabel / metric_relabel

Scrape 시 라벨 변경:
- `__meta_kubernetes_*` 를 의미있는 라벨로 변환
- 불필요한 라벨 drop

ServiceMonitor 의 `metricRelabelings`:
```yaml
metricRelabelings:
  - sourceLabels: [__name__]
    regex: 'go_gc_.*'
    action: drop          # 이 메트릭들 제외
```

→ cardinality / 디스크 절감.

## 8. Federation

대규모 운영에서 여러 Prometheus 를 계층화:
```
[Edge Prom-1]  [Edge Prom-2]  [Edge Prom-3]   ← 각 클러스터
       ↓             ↓             ↓
       └──── /federate ────────────┘
                     ↓
            [Aggregator Prom]                  ← 중앙 집계
```

`/federate` endpoint 로 다른 Prometheus 의 메트릭을 가져옴. 단점: 자체 TSDB 라 장기 저장 한계 → 다음 모듈의 Thanos / Mimir.

## 9. remote_write / remote_read

원격 저장소로 메트릭 push:
```yaml
prometheus.spec:
  remoteWrite:
    - url: https://aps-workspaces.../api/v1/remote_write
      sigv4:
        region: ap-northeast-2
```

AWS Managed Prometheus (AMP), Grafana Mimir, VictoriaMetrics 등으로 보냄.

다음: [lab-01-scrape-anatomy.md](./lab-01-scrape-anatomy.md)
