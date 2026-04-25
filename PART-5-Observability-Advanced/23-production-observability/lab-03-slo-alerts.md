# Lab 03 — Multi-Burn-Rate SLO Alert

## 1. SLO 정의

order-service 의 가용성 SLO:
- **Target**: 99.9% (30일 rolling window)
- **Error Budget**: 0.1% = 30일 × 1440분 × 0.001 = 43.2 분

이 budget 을 "얼마나 빠르게" 소진하는지 → burn rate.

## 2. SLO Recording + Alert Rule 적용

```bash
kubectl apply -f manifests/slo-rules.yaml
kubectl get prometheusrule -n monitoring order-service-slo
```

## 3. 인위적으로 5xx 발생시키기

order-service 의 일부 path 에 의도적으로 5xx 응답하게:
```bash
# (현재 order-service 는 정상 응답만 함. 시뮬레이션:)
# 가짜 5xx 메트릭 push (Pushgateway 사용 또는 메트릭 직접 주입은 어려움)
# 대신 부하를 많이 줘서 OOM/Throttling 으로 5xx 유발
```

또는 메트릭 직접 manipulation 어려우니 **alert rule 을 임시로 임계 낮춤**:
```bash
kubectl patch prometheusrule -n monitoring order-service-slo --type='json' -p='[
  {"op":"replace","path":"/spec/groups/1/rules/0/expr","value":"vector(1)"}
]'
```

→ 항상 true → 즉시 fire 시작.

## 4. Alert 동작 확인

http://localhost:9090/alerts → `OrderServiceSLOBurnRateFast` 가 `Pending` → 2분 후 `Firing`.

## 5. Burn rate 계산 이해

```
SLO target = 99.9% (30d)
Error budget = 0.1%

Fast burn:
  1시간 안에 budget 의 2% 소진하면 fast
  budget burn rate = 14.4 (= 30d / 30d × 1/720 hour × 2%) — 단위가 budget/hour
  실제 error rate = 14.4 × 0.001 = 0.0144 = 1.44%

Slow burn:
  6시간 안에 budget 의 5% 소진
  burn rate = 1 (= 30d × 1/180 day × 5%)
  실제 error rate = 1 × 0.001 = 0.001 = 0.1%
```

이 값은 Google SRE Workbook 의 multi-burn-rate 공식. 다른 SLO 면 다른 값.

## 6. 두 burn rate 가 동시 만족 (and) 인 이유

- Fast 만 있으면: 1분 spike 후 정상 복귀해도 alert
- Slow 만 있으면: 큰 사고 (50% error 5분간) 도 평균이 낮아 잡지 못함
- **둘 다**: 5분 평균 + 1시간 평균 모두 임계 → 진짜 sustained 문제

## 7. SLO Dashboard

Grafana 에서 변수 + 패널:
- Stat: Current SLO compliance (`sli:order_service_availability:ratio_30d`)
- Time series: Error budget remaining over time
- Burn rate gauge

## 8. 원복

```bash
kubectl apply -f manifests/slo-rules.yaml    # 원래대로
```

## 학습 확인

1. SLO 99.9% 와 99.99% 의 budget 차이는?
2. multi-burn-rate 가 single-rate alert 보다 좋은 두 가지는?
3. SLO 가 너무 엄격하면 어떤 부작용?

다음: [lab-04-alertmanager-routing.md](./lab-04-alertmanager-routing.md)
