# Lab 03 — Grafana Unified Alerting

## 1. Grafana Alerting 활성화 확인

http://localhost:3000 → 좌측 Alerting 메뉴.

기본은 active. Helm values 에서 토글 가능 (`grafana.alerting.unifiedAlerting.enabled`).

## 2. Contact Point 설정

Alerting → Contact points → New contact point.

옵션들:
- Email
- Slack (webhook URL)
- PagerDuty
- Webhook (custom)
- ...

학습용 — Webhook 으로 webhook.site 같은 테스트 endpoint:
- Name: `test-webhook`
- Type: Webhook
- URL: https://webhook.site/<unique-id>

## 3. Notification Policy

Alerting → Notification policies. Default policy 와 routing.

```
Default: contact point = test-webhook
  ├── matchers: severity=critical → contact point = pagerduty
  └── matchers: severity=warning  → contact point = slack-warning
```

## 4. Alert Rule 만들기 (UI)

Alerting → Alert rules → New rule.

### 4.1 Grafana managed (datasource agnostic)

Section A — Set query:
- Datasource: Prometheus
- Query: `sum by (service) (rate(http_requests_total{code=~"5.."}[5m])) / sum by (service) (rate(http_requests_total[5m]))`

Section B — Define alert:
- Reduce: `last()` 또는 `mean()`
- Threshold: `IS ABOVE 0.05`

Section C — Set evaluation:
- Folder: `EKS-Study`
- Group: `web-alerts`
- Evaluation: every `1m` for `5m`

Section D — Annotations + labels:
- summary: "{{ $labels.service }} error rate {{ humanizePercentage $value }}"
- severity: warning

Save.

## 5. Alert State

Alerting → Alert rules → 위 규칙:
- Normal — 조건 미충족
- Pending — 충족 시작 (for 안 끝남)
- Firing — for 끝나고 통지 발송

## 6. Code 로 Alert Rule (provisioning)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-alerts
  namespace: monitoring
  labels:
    grafana_alert: "1"
data:
  alerts.yaml: |
    apiVersion: 1
    groups:
      - orgId: 1
        name: web
        folder: EKS-Study
        interval: 1m
        rules:
          - uid: high-error-rate
            title: High Error Rate
            condition: B
            data:
              - refId: A
                datasourceUid: prometheus
                model:
                  expr: 'sum by (service) (rate(http_requests_total{code=~"5.."}[5m])) / sum by (service) (rate(http_requests_total[5m]))'
              - refId: B
                datasourceUid: __expr__
                model:
                  type: threshold
                  expression: A
                  conditions:
                    - evaluator: {type: gt, params: [0.05]}
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "{{ $labels.service }} error rate {{ humanizePercentage $value }}"
```

## 7. Grafana Alerting vs Prometheus Alertmanager

| | Grafana Alerting | Prometheus Alertmanager |
|---|---|---|
| 데이터 소스 | 모든 datasource | Prometheus 만 |
| 평가 | Grafana 가 | Prometheus 가 |
| 라우팅 | Grafana 의 Notification policies | Alertmanager config |
| Multi-cluster | 한 Grafana 에서 통합 | 클러스터별 Alertmanager |
| 코드화 | provisioning ConfigMap | PrometheusRule CRD |

권장:
- 단일 클러스터 / Prometheus 중심 → **Alertmanager**
- 다중 datasource (CloudWatch + Prom + Loki) → **Grafana Alerting**
- 둘 다 → 가능 but 알람 중복 주의

## 학습 확인

1. Grafana Alerting 의 평가 주체는?
2. Prometheus Alertmanager 와 Grafana Alerting 을 동시 사용 시 주의점?
3. Webhook contact point 의 페이로드 형식은?

다음: [quiz.md](./quiz.md)
