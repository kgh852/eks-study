# Lab 02 — 5개 서비스에 메트릭 적용

## 1. order-service (Gin)

`scenarios/order-service/main.go` 의 router 셋업 부분 수정:

```go
package main

import (
    "log/slog"
    "net/http"

    "github.com/finn/eks-study/order-service/handler"
    "github.com/finn/eks-study/shared/config"
    "github.com/finn/eks-study/shared/logger"
    "github.com/finn/eks-study/shared/metrics"
    "github.com/gin-gonic/gin"
)

func main() {
    log := logger.New("order-service")
    port := config.GetString("PORT", "8080")

    r := gin.New()
    r.Use(gin.Recovery())
    r.Use(metrics.GinMiddleware("order-service"))   // ← 한 줄 추가
    h := handler.New()
    r.POST("/orders", h.Create)
    r.GET("/orders/:id", h.Get)
    r.GET("/healthz", func(c *gin.Context) { c.Status(http.StatusOK) })

    go func() {
        mux := http.NewServeMux()
        mux.Handle("/metrics", metrics.Handler())
        if err := http.ListenAndServe(":9090", mux); err != nil {
            log.Error("metrics server failed", "err", err)
        }
    }()

    log.Info("starting", "port", port)
    if err := r.Run(":" + port); err != nil {
        slog.Error("server failed", "err", err)
    }
}
```

## 2. frontend (net/http)

frontend 는 Gin 이 아니라 net/http 사용. middleware 도 net/http 형태로:

`scenarios/frontend/main.go`:
```go
package main

import (
    "net/http"
    "strconv"
    "time"

    "github.com/finn/eks-study/frontend/handler"
    cfg "github.com/finn/eks-study/shared/config"
    "github.com/finn/eks-study/shared/logger"
    "github.com/finn/eks-study/shared/metrics"
)

// statusRecorder for net/http
type statusRecorder struct {
    http.ResponseWriter
    code int
}

func (r *statusRecorder) WriteHeader(code int) {
    r.code = code
    r.ResponseWriter.WriteHeader(code)
}

func instrument(next http.HandlerFunc, route string) http.HandlerFunc {
    httpReq := metrics.Counter("http_requests_total", "...", []string{"service","method","path","code"})
    httpDur := metrics.Histogram("http_request_duration_seconds", "...", []string{"service","method","path"}, nil)

    return func(w http.ResponseWriter, r *http.Request) {
        rec := &statusRecorder{ResponseWriter: w, code: 200}
        start := time.Now()
        next(rec, r)
        d := time.Since(start).Seconds()
        httpReq.WithLabelValues("frontend", r.Method, route, strconv.Itoa(rec.code)).Inc()
        httpDur.WithLabelValues("frontend", r.Method, route).Observe(d)
    }
}

func main() {
    log := logger.New("frontend")
    port := cfg.GetString("PORT", "8080")

    h, err := handler.New("templates/*.html")
    if err != nil { log.Error("template parse", "err", err); return }

    mux := http.NewServeMux()
    mux.HandleFunc("/", instrument(h.Index, "/"))
    mux.HandleFunc("/healthz", instrument(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) }, "/healthz"))
    mux.Handle("/metrics", metrics.Handler())

    log.Info("frontend starting", "port", port)
    if err := http.ListenAndServe(":"+port, mux); err != nil {
        log.Error("listen", "err", err)
    }
}
```

> 위 instrument 헬퍼는 매번 새 메트릭을 등록하지 않도록 init 또는 변수로 빼는 게 더 좋음 (학습용 단순화).

## 3. payment-service (SQS Worker)

HTTP 가 없으니 RED 가 아니라 **워커 메트릭**:
- 처리한 메시지 수 (Counter)
- 실패한 메시지 수 (Counter)
- 메시지 처리 시간 (Histogram)
- 큐 폴링 빈도 (Gauge)

`scenarios/payment-service/main.go`:
```go
import (
    // ...
    "github.com/finn/eks-study/shared/metrics"
)

var (
    msgsTotal = metrics.Counter("payment_messages_total", "Processed messages",
        []string{"result"})    // result: success / fail
    msgDuration = metrics.Histogram("payment_processing_seconds", "Per-message processing",
        []string{}, []float64{0.001, 0.01, 0.1, 0.5, 1, 5, 10})
)

func main() {
    // ... existing setup ...

    c.Handler = func(ctx context.Context, payload []byte) error {
        start := time.Now()
        var msg map[string]any
        err := json.Unmarshal(payload, &msg)
        if err != nil {
            msgsTotal.WithLabelValues("fail").Inc()
            return err
        }
        log.Info("processed payment", "msg", msg)
        msgsTotal.WithLabelValues("success").Inc()
        msgDuration.WithLabelValues().Observe(time.Since(start).Seconds())
        return nil
    }
    // ...
}
```

## 4. notification-service (Kafka Worker)

같은 패턴 — 워커 메트릭:
```go
var (
    notifTotal = metrics.Counter("notification_messages_total", "Sent notifications",
        []string{"result"})
    notifDuration = metrics.Histogram("notification_processing_seconds", "Per-message",
        []string{}, []float64{0.001, 0.01, 0.1, 0.5, 1, 5})
)
```

## 5. user-service (gRPC)

gRPC 는 라이브러리가 다름. Prometheus interceptor 사용:
```bash
cd /Users/finn/test/eks-study/scenarios/user-service
go get github.com/grpc-ecosystem/go-grpc-middleware/v2/interceptors/prometheus
```

`main.go`:
```go
import (
    grpcprom "github.com/grpc-ecosystem/go-grpc-prometheus"
)

func main() {
    // ...
    s := grpc.NewServer(
        grpc.ChainUnaryInterceptor(grpcprom.UnaryServerInterceptor),
        grpc.ChainStreamInterceptor(grpcprom.StreamServerInterceptor),
    )
    pb.RegisterUserServiceServer(s, server.New())
    grpcprom.Register(s)    // 메트릭 초기 0 으로 등록
    // ...
}
```

→ 자동으로 `grpc_server_handled_total`, `grpc_server_handling_seconds_bucket` 등 노출.

## 6. 빌드 + 테스트

```bash
cd /Users/finn/test/eks-study/scenarios
make test
make build
```

## 7. 도커 이미지 재빌드 + ECR 푸시

```bash
make docker
make ecr-push
```

## 8. EKS 의 워크로드 재배포

```bash
kubectl rollout restart deploy -n order
```

## 9. 메트릭 노출 검증

```bash
# Pod 내부에서 /metrics 확인
POD=$(kubectl get pods -n order -l app.kubernetes.io/name=order-service -o name | head -1)
kubectl exec -n order $POD -- wget -qO- localhost:9090/metrics | grep -E '^http_requests_total|^http_request_duration_seconds_bucket' | head -10
```

기대:
```
http_requests_total{code="200",method="POST",path="/orders",service="order-service"} 5
http_request_duration_seconds_bucket{le="0.005",method="POST",path="/orders",service="order-service"} 3
...
```

## 10. Prometheus 에서 새 메트릭 쿼리

http://localhost:9090/graph

```promql
sum by (service, path) (rate(http_requests_total[1m]))
histogram_quantile(0.99, sum by (le, service, path) (rate(http_request_duration_seconds_bucket[5m])))
```

→ Module 20 의 recording rule 들이 이제 실제 데이터 채워짐.

## 학습 확인

1. payment-service 의 메트릭이 RED 와 다른 이유 (왜 워커는 다름)?
2. gRPC 의 status code 가 HTTP 와 다른 점 (메트릭 라벨 관점)?
3. 동일한 메트릭 이름으로 서비스 별 다른 라벨 쓰는 게 좋을까, 별도 메트릭이 좋을까?

다음: [quiz.md](./quiz.md)
