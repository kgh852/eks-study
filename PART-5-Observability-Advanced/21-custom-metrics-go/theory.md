# 이론 — prometheus/client_golang

## 1. 메트릭 등록 모델

```go
import "github.com/prometheus/client_golang/prometheus"

// 1. 메트릭 정의
var requestsTotal = prometheus.NewCounterVec(
    prometheus.CounterOpts{
        Name: "http_requests_total",
        Help: "Total HTTP requests",
    },
    []string{"method", "path", "code"},     // 라벨
)

// 2. 등록
func init() {
    prometheus.MustRegister(requestsTotal)
}

// 3. 사용
requestsTotal.WithLabelValues("POST", "/orders", "200").Inc()
```

## 2. 메트릭 타입별 API

### 2.1 Counter / CounterVec
```go
var counter = prometheus.NewCounter(prometheus.CounterOpts{Name: "x_total"})
counter.Inc()
counter.Add(5)

var counterVec = prometheus.NewCounterVec(
    prometheus.CounterOpts{Name: "y_total"},
    []string{"label1", "label2"},
)
counterVec.WithLabelValues("a", "b").Inc()
```

### 2.2 Gauge / GaugeVec
```go
var gauge = prometheus.NewGauge(prometheus.GaugeOpts{Name: "active_connections"})
gauge.Inc()
gauge.Dec()
gauge.Set(42)
```

### 2.3 Histogram / HistogramVec
```go
var hist = prometheus.NewHistogramVec(
    prometheus.HistogramOpts{
        Name: "request_duration_seconds",
        Buckets: prometheus.DefBuckets,    // 또는 커스텀: []float64{.005, .01, .025, ...}
    },
    []string{"method", "path"},
)

// 사용
start := time.Now()
// ... 처리 ...
hist.WithLabelValues("POST", "/orders").Observe(time.Since(start).Seconds())
```

`DefBuckets`: `.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10` (초 단위 — HTTP 적합).

### 2.4 Summary
**가급적 사용 자제** (분산 환경 quantile 합산 불가).

## 3. 라벨 설계 best practice

### 좋은 라벨
- `method`: GET/POST/...   (값 4~7개)
- `path`: 라우트 패턴 (값 N개 — N = 라우트 수)
- `code`: HTTP status (200, 4xx, 5xx 그룹화 권장)

### 나쁜 라벨
- `user_id`, `request_id`, `email` — cardinality 폭발
- `timestamp` — 무한
- `random` — 무한

### path 라벨의 함정

```go
// ❌ /orders/abc-123-def 의 abc-123-def 가 path 로
labelValues := r.URL.Path

// ✅ 라우트 패턴 사용
labelValues := matchedRoute   // /orders/:id
```

Gin / Echo / chi 모두 matched route 를 노출.

## 4. promhttp.Handler 로 endpoint 노출

```go
import "github.com/prometheus/client_golang/prometheus/promhttp"

http.Handle("/metrics", promhttp.Handler())
```

`promhttp.Handler()` 는 **모든 등록된 메트릭** 을 자동으로 노출.

### 별도 포트 권장
앱 트래픽 (8080) 과 메트릭 (9090) 분리 — Prometheus 가 앱 포트로 뚫지 않게.

## 5. middleware 패턴 (Gin 예시)

```go
func PrometheusMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        start := time.Now()
        c.Next()    // 핸들러 실행

        duration := time.Since(start).Seconds()
        path := c.FullPath()         // 라우트 패턴 (e.g., "/orders/:id")
        status := strconv.Itoa(c.Writer.Status())
        method := c.Request.Method

        requestsTotal.WithLabelValues(method, path, status).Inc()
        requestDuration.WithLabelValues(method, path).Observe(duration)
    }
}
```

## 6. Histogram bucket 설계

기본 `DefBuckets` 는 일반 HTTP 적합. 그러나 워크로드 특성에 맞춰 조정:

- API 게이트웨이: `[.001, .005, .01, .025, .05, .1, .25, .5, 1]` (낮은 값에 더 dense)
- 배치 작업: `[1, 5, 10, 30, 60, 300, 600]` (분 단위)
- gRPC: `[.001, .002, .005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5]`

너무 많은 bucket → cardinality (`bucket × 라벨 조합`).

## 7. 표준 메트릭 (Go runtime / process)

`promhttp.Handler()` 가 자동 노출하는 표준 메트릭:
- `go_goroutines`, `go_memstats_*` — Go runtime
- `process_cpu_seconds_total`, `process_resident_memory_bytes` — OS process

대시보드 (Grafana ID 6671 — Go Processes) 그대로 사용 가능.

## 8. 추천 패턴 — `shared/metrics` 라이브러리

본 커리큘럼 다음 lab 에서 `shared/metrics/` 를 확장:
- 모든 서비스가 표준 메트릭 자동 노출
- `RED()` 헬퍼로 middleware 한 줄 적용
- `Gauge()`, `Counter()` 빌더로 커스텀 추가

다음: [lab-01-shared-metrics.md](./lab-01-shared-metrics.md)
