# 이론 — Production Observability

## 1. Prometheus HA — 두 가지 접근

### 1.1 다중 replicas (단순)

```yaml
prometheus.spec:
  replicas: 2
```

→ 두 Prometheus 가 같은 target 들을 각자 scrape. 중복 데이터.

**문제**:
- Grafana 가 두 source 를 동시 쓰면 그래프 중복
- 시각적으로 차이 (slight time skew)

**해결**: Querier (Thanos) 또는 dedup proxy 가 위에 위치 → Grafana 는 한 endpoint.

### 1.2 단일 + remote_write (중앙 저장소)

각 클러스터 (또는 region) Prometheus 1개 + remote_write 로 중앙 저장:

```yaml
remoteWrite:
  - url: https://central-storage/api/v1/write
```

중앙 저장소: Thanos / Mimir / Cortex / VictoriaMetrics / AMP.

→ HA 는 중앙 저장소가 책임.

## 2. 장기 저장 옵션 비교

### 2.1 Thanos
- Prometheus 옆 sidecar → S3 로 chunk 업로드
- Querier 가 여러 Prom + S3 통합 쿼리
- **장점**: 무한 retention (S3 비용만), Prom 기반이라 호환성 ↑
- **단점**: 컴포넌트 다수 (sidecar/store/compactor/querier)

### 2.2 Grafana Mimir / Cortex
- Push 기반 (remote_write)
- Multi-tenant 우수 (SaaS 수준)
- Microservices 아키텍처

### 2.3 AWS Managed Prometheus (AMP)
- AWS 가 운영하는 Cortex 호환 서비스
- IAM 인증 (sigv4)
- 15개월 retention
- 비용: ingestion + query 별
- **장점**: 운영 부담 0
- **단점**: AWS lock-in

### 2.4 VictoriaMetrics
- 단일 바이너리 (간단)
- 디스크/메모리 효율 ↑
- 일부 PromQL 호환성 차이

| | Thanos | Mimir | AMP | VM |
|---|---|---|---|---|
| 운영 부담 | 중 | 높 | 0 | 낮 |
| 비용 | S3 + Querier | 자체 운영 | per-sample | 자체 운영 |
| HA | ✓ | ✓ | ✓ | ✓ |
| 무한 retention | S3 | S3/GCS | 15개월 | 자체 디스크 |

**학습 환경**: AMP 추천 (AWS 자원 활용 + 운영 부담 0).

## 3. SLI / SLO / Error Budget

### 3.1 정의

- **SLI** (Service Level Indicator) — 측정 메트릭 (예: 5xx 비율)
- **SLO** (Service Level Objective) — 목표 (예: 5xx < 0.1% over 30d)
- **Error Budget** — 1 - SLO. 이 만큼은 "허용된 에러"

### 3.2 좋은 SLI 의 특징

- **사용자 경험 반영** — 5xx 비율, p99 latency, 응답률
- **측정 가능** — Prometheus 메트릭으로
- **단순** — 하나의 숫자

흔한 SLI:
- **Availability**: `successful_requests / total_requests`
- **Latency**: `requests_under_500ms / total_requests`
- **Quality**: `requests_with_correct_data / total_requests`

### 3.3 SLO 정의

```
SLO: 30일 동안 99.9% 의 요청이 성공
Error Budget: 0.1% = 30일 × 24h × 60min × 0.001 = 43.2분 down time
```

## 4. Multi-Burn-Rate Alert

기본 alert (`error_rate > 0.01 for 5m`) 의 문제:
- 빠른 사고 (1분 100% down) → 5m for 동안 통지 늦음
- 느린 사고 (10시간 동안 1% 에러) → 알림 안 옴 (임계 미달)

**Multi-burn-rate**: 두 윈도우 동시 평가:

```yaml
- alert: ErrorBudgetBurning_Fast
  expr: |
    sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 0.144 and
    sum(rate(http_requests_total{status=~"5.."}[1h])) / sum(rate(http_requests_total[1h])) > 0.144
  for: 2m
  labels:
    severity: critical

- alert: ErrorBudgetBurning_Slow
  expr: |
    sum(rate(http_requests_total{status=~"5.."}[1h])) / sum(rate(http_requests_total[1h])) > 0.018 and
    sum(rate(http_requests_total{status=~"5.."}[6h])) / sum(rate(http_requests_total[6h])) > 0.018
  for: 15m
  labels:
    severity: warning
```

각 burn rate 값은 SLO 와 budget consumption 시간으로 계산. 자세한 계산은 Google SRE Workbook 참고.

## 5. Alertmanager 라우팅 / 억제 / 묵음

### 5.1 라우팅 (route)

```yaml
route:
  group_by: [alertname, namespace]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: default-slack
  routes:
    - matchers: [severity="critical"]
      receiver: pagerduty
      continue: true     # → 추가로 default 도 받음
    - matchers: [team="platform"]
      receiver: platform-slack
```

### 5.2 억제 (inhibition)

심각한 alert 가 firing 이면 덜 심각한 같은 시리즈 억제:
```yaml
inhibit_rules:
  - source_matchers: [severity="critical"]
    target_matchers: [severity="warning"]
    equal: [namespace, service]
```

→ critical 발생 시 같은 NS+service 의 warning 무시.

### 5.3 묵음 (silence)

운영 작업 (배포 / 점검) 중 일시적 alert 차단.
- Alertmanager UI 에서 시작 / 종료 시각 + matchers 입력
- API: `amtool silence add`

## 6. Runbook annotation

alert 가 firing 시 즉시 무엇을 해야 할지:

```yaml
annotations:
  summary: "..."
  runbook_url: "https://wiki.example.com/runbooks/{{ $labels.alertname }}"
```

→ Slack 통지에 link 포함. on-call 이 즉시 절차 확인.

## 7. Distributed Tracing 미리보기

본 커리큘럼 범위 외지만 언급:
- AWS X-Ray, Tempo, Jaeger
- OpenTelemetry SDK 로 앱 수정
- TraceID 를 로그/메트릭에 포함 → 3축 연결

다음: [lab-01-ha-prometheus.md](./lab-01-ha-prometheus.md)
