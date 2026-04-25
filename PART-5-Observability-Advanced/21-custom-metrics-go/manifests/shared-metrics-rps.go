// 본 파일은 lab-01 의 참고 코드. 실제로는 scenarios/shared/metrics/metrics.go 를 다음 내용으로 교체.

package metrics

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// 표준 RED 메트릭들 — 모든 서비스 공유
var (
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "HTTP requests grouped by method, path, and code.",
		},
		[]string{"service", "method", "path", "code"},
	)

	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request duration distribution.",
			Buckets: []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5},
		},
		[]string{"service", "method", "path"},
	)

	inFlight = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "http_requests_in_flight",
			Help: "Currently in-flight HTTP requests.",
		},
		[]string{"service"},
	)
)

// Handler — /metrics 핸들러 (기존 함수 유지)
func Handler() http.Handler {
	return promhttp.Handler()
}

// GinMiddleware — Gin 라우터에 RED 메트릭 자동 적용
func GinMiddleware(serviceName string) gin.HandlerFunc {
	return func(c *gin.Context) {
		inFlight.WithLabelValues(serviceName).Inc()
		defer inFlight.WithLabelValues(serviceName).Dec()

		start := time.Now()
		c.Next()
		duration := time.Since(start).Seconds()

		path := c.FullPath()
		if path == "" {
			path = "<unmatched>"
		}
		code := strconv.Itoa(c.Writer.Status())
		method := c.Request.Method

		httpRequestsTotal.WithLabelValues(serviceName, method, path, code).Inc()
		httpRequestDuration.WithLabelValues(serviceName, method, path).Observe(duration)
	}
}

// Counter — 커스텀 Counter 등록 헬퍼
func Counter(name, help string, labels []string) *prometheus.CounterVec {
	return promauto.NewCounterVec(
		prometheus.CounterOpts{Name: name, Help: help},
		labels,
	)
}

// Gauge — 커스텀 Gauge 등록 헬퍼
func Gauge(name, help string, labels []string) *prometheus.GaugeVec {
	return promauto.NewGaugeVec(
		prometheus.GaugeOpts{Name: name, Help: help},
		labels,
	)
}

// Histogram — 커스텀 Histogram (기본 bucket 또는 명시)
func Histogram(name, help string, labels []string, buckets []float64) *prometheus.HistogramVec {
	if buckets == nil {
		buckets = prometheus.DefBuckets
	}
	return promauto.NewHistogramVec(
		prometheus.HistogramOpts{Name: name, Help: help, Buckets: buckets},
		labels,
	)
}
