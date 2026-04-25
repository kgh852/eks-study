# Lab 01 — shared/metrics 확장

목표: `scenarios/shared/metrics/metrics.go` 를 RED 메트릭 자동 노출하도록 확장.

## 1. 현재 코드 확인

```bash
cat /Users/finn/test/eks-study/scenarios/shared/metrics/metrics.go
```

기대 (P0 에서 만든 단순 버전):
```go
package metrics

import (
    "net/http"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

func Handler() http.Handler {
    return promhttp.Handler()
}
```

## 2. 새 코드로 교체

본 모듈의 `manifests/shared-metrics-rps.go` 를 그대로 복사:

```bash
cp /Users/finn/test/eks-study/PART-5-Observability-Advanced/21-custom-metrics-go/manifests/shared-metrics-rps.go \
   /Users/finn/test/eks-study/scenarios/shared/metrics/metrics.go
```

## 3. 의존성 추가 (gin)

shared 가 gin import 하게 됨:
```bash
cd /Users/finn/test/eks-study/scenarios/shared
go get github.com/gin-gonic/gin
```

## 4. 단위 테스트 추가

`scenarios/shared/metrics/metrics_test.go`:
```go
package metrics

import (
    "io"
    "net/http"
    "net/http/httptest"
    "strings"
    "testing"

    "github.com/gin-gonic/gin"
)

func TestGinMiddlewareRecordsMetrics(t *testing.T) {
    gin.SetMode(gin.TestMode)
    r := gin.New()
    r.Use(GinMiddleware("test-service"))
    r.GET("/hello/:name", func(c *gin.Context) { c.String(200, "ok") })

    w := httptest.NewRecorder()
    req := httptest.NewRequest("GET", "/hello/world", nil)
    r.ServeHTTP(w, req)

    if w.Code != 200 {
        t.Fatalf("expected 200, got %d", w.Code)
    }

    // /metrics 호출하여 우리 메트릭이 노출되는지
    mw := httptest.NewRecorder()
    Handler().ServeHTTP(mw, httptest.NewRequest("GET", "/metrics", nil))
    body, _ := io.ReadAll(mw.Body)
    text := string(body)

    if !strings.Contains(text, `http_requests_total{`) {
        t.Errorf("expected http_requests_total in metrics output")
    }
    if !strings.Contains(text, `service="test-service"`) {
        t.Errorf("expected service label")
    }
    if !strings.Contains(text, `path="/hello/:name"`) {
        t.Errorf("expected route pattern as path label, got body:\n%s", text[:min(2000,len(text))])
    }
}

func min(a, b int) int { if a < b { return a }; return b }

func TestCounterAndGaugeHelpers(t *testing.T) {
    c := Counter("test_counter", "test", []string{"x"})
    c.WithLabelValues("a").Inc()
    g := Gauge("test_gauge", "test", []string{"y"})
    g.WithLabelValues("b").Set(42)

    h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { Handler().ServeHTTP(w, r) })
    w := httptest.NewRecorder()
    h.ServeHTTP(w, httptest.NewRequest("GET", "/metrics", nil))
    body, _ := io.ReadAll(w.Body)

    for _, want := range []string{`test_counter{x="a"}`, `test_gauge{y="b"} 42`} {
        if !strings.Contains(string(body), want) {
            t.Errorf("missing: %s", want)
        }
    }
}
```

## 5. 테스트 실행

```bash
cd /Users/finn/test/eks-study/scenarios/shared
go test ./metrics/... -v
```

기대: 두 테스트 PASS.

## 6. 빌드 검증

```bash
go build ./...
```

기대: 에러 없음.

## 7. 다른 서비스도 빌드 가능 여부

```bash
cd /Users/finn/test/eks-study/scenarios
make test
```

기대: 모든 서비스 테스트 PASS (아직 middleware 적용 전이라 동작은 같음).

## 학습 확인

1. `promauto.NewCounterVec` 와 `prometheus.NewCounterVec` + `MustRegister` 의 차이는?
2. `c.FullPath()` 와 `c.Request.URL.Path` 의 라벨 cardinality 관점 차이는?
3. `inFlight` Gauge 가 RED 패턴의 어디에 해당? (R/E/D 외 추가)

다음: [lab-02-instrument-services.md](./lab-02-instrument-services.md)
