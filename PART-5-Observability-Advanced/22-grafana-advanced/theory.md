# 이론 — Grafana 심화

## 1. Datasource

Grafana 가 데이터를 가져오는 외부 시스템:
- Prometheus (가장 흔함)
- CloudWatch
- Loki (로그)
- Tempo (트레이스)
- MySQL / Postgres
- Elasticsearch

여러 datasource 동시 사용 가능 → 한 대시보드 안에서 metrics + logs + traces.

## 2. Panel 종류

- **Time series** — 시간 축 그래프 (가장 흔함)
- **Stat** — 단일 큰 숫자
- **Gauge** — 게이지 (0 ~ 100%)
- **Bar gauge** — 다중 값 비교
- **Table** — 테이블
- **Heatmap** — 히트맵 (latency 분포 시각화 강력)
- **Logs** — Loki 결과
- **Trace** — Tempo 결과

## 3. Variables — 동적 drop-down

대시보드 상단의 drop-down 으로 query 의 일부를 사용자가 선택.

### 3.1 Query 변수

```
Name: namespace
Type: Query
Datasource: Prometheus
Query: label_values(kube_pod_info, namespace)
```

→ Prometheus 에서 namespace 라벨 unique 값들을 자동 채움.

### 3.2 사용
PromQL 안에 `$namespace`:
```
sum by (pod) (rate(http_requests_total{namespace="$namespace"}[1m]))
```

### 3.3 다른 변수 타입
- Constant — 상수
- Custom — 직접 입력
- Interval — `1m`, `5m`, `1h` (집계 단위)
- Datasource — 데이터소스 선택
- Text box — 자유 입력

### 3.4 Cascading
한 변수가 다른 변수에 의존:
```
$namespace ─→ $pod (Query: label_values(kube_pod_info{namespace="$namespace"}, pod))
```

## 4. Annotations

대시보드 위에 **이벤트 마커** 표시:
- 배포 시각
- 사고 시각
- alert 발생 시각

```yaml
# Datasource: Prometheus
# Query: ALERTS{alertstate="firing"}
```

→ alert 발생 시점이 그래프 위에 빨간 줄.

## 5. Links

- **Dashboard links**: 한 대시보드 → 다른 대시보드 (변수 전달)
- **Panel links**: 패널 → 외부 URL
- **Data links**: 데이터 포인트 클릭 → URL (예: pod 이름 클릭 → kubectl describe 페이지)

## 6. Provisioning — 대시보드를 코드로 관리

GUI 로 만든 대시보드를 git 에 저장 → 재배포 시 자동 적용.

### 6.1 ConfigMap 기반 (kube-prometheus-stack 의 sidecar)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-dashboard
  labels:
    grafana_dashboard: "1"     # ← sidecar 가 이 라벨 monitor
data:
  my-dashboard.json: |
    {
      "title": "My Dashboard",
      "panels": [...]
    }
```

→ Grafana sidecar 가 자동 import.

### 6.2 Datasource provisioning

```yaml
apiVersion: 1
datasources:
  - name: Prometheus-DC1
    type: prometheus
    url: http://prom-dc1:9090
  - name: Prometheus-DC2
    type: prometheus
    url: http://prom-dc2:9090
```

## 7. Grafana 자체 Alerting (Unified Alerting)

Grafana 9+ 에서 통합 alerting:
- Prometheus / CloudWatch / Loki 등 **모든 datasource** 의 데이터로 alert
- Alertmanager 와 별도 (또는 Alertmanager 통합 가능)
- Slack, PagerDuty 등 contact point 통합

### 7.1 Alert Rule 만들기 (UI)
1. 대시보드 패널 → Alert 탭
2. Query 정의 (Prometheus / CloudWatch / ...)
3. Condition (예: `WHEN avg() OF query(A, 5m, now) IS ABOVE 0.05`)
4. Evaluation interval + for
5. Notification: contact point 선택

### 7.2 Code-based (UI 만든 후 export 또는 직접 작성)
```yaml
groups:
  - name: web-alerts
    rules:
      - uid: high-latency
        title: High Latency
        condition: A
        data:
          - refId: A
            datasourceUid: prometheus-uid
            model:
              expr: 'histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))'
        for: 5m
```

## 8. 대시보드 디자인 best practice

1. **Top → Bottom** 정보의 폭 순 (overview → detail)
2. **단위 표시** (rps, %, ms, MB)
3. **색상 일관성** — green=good, red=bad
4. **임계값 표시** (Stat / Gauge 패널의 threshold)
5. **변수로 재사용성** — 같은 대시보드를 NS / 환경 별로
6. **너무 많은 패널 X** — 한 화면에 8~12개 권장

다음: [lab-01-variables.md](./lab-01-variables.md)
