# Lab 03 — OpenCost (NS / Workload 단위 비용 배분)

## 1. 사전 — Prometheus 떠 있어야 함

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
```

## 2. OpenCost 설치

```bash
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm repo update

helm install opencost opencost/opencost \
  -n opencost --create-namespace \
  --set opencost.exporter.defaultClusterId=eks-study \
  --set opencost.prometheus.internal.enabled=false \
  --set opencost.prometheus.external.enabled=true \
  --set opencost.prometheus.external.url="http://kps-kube-prometheus-stack-prometheus.monitoring:9090"

kubectl get pods -n opencost
```

기대:
```
NAME                        READY   STATUS    RESTARTS   AGE
opencost-xxx                2/2     Running   0          1m
```

## 3. UI 접근

```bash
kubectl port-forward -n opencost svc/opencost 9090:9090 &
```

> OpenCost UI 는 9090 (Prometheus 와 충돌 주의 — 다른 포트로 방향 전환 또는 백그라운드 정지)

```bash
kubectl port-forward -n opencost svc/opencost 9003:9003 &
```

브라우저: http://localhost:9003

탭들:
- **Cost Allocation** — Namespace / Pod / 라벨 단위 비용
- **Assets** — Node / 디스크 비용
- **Savings** — 절감 추천

## 4. NS 별 비용 (CLI)

OpenCost 의 API:
```bash
curl -s 'http://localhost:9003/allocation' \
  --data-urlencode 'window=24h' \
  --data-urlencode 'aggregate=namespace' \
  -G | jq '.data[0] | to_entries[] | {ns: .key, cost: .value.totalCost}' | head -20
```

기대 (예시):
```json
{"ns":"kube-system","cost":2.45}
{"ns":"order","cost":1.20}
{"ns":"monitoring","cost":3.10}
```

## 5. 시간대별 비용 추이

```bash
curl -s 'http://localhost:9003/allocation' \
  --data-urlencode 'window=7d' \
  --data-urlencode 'aggregate=namespace' \
  --data-urlencode 'step=24h' \
  -G | jq '.data | length'
```

→ 일 단위로 7개 결과.

## 6. 라벨 기반 비용 (팀 단위)

Pod 에 `team=alpha` 라벨이 붙어 있다면:
```bash
curl -s 'http://localhost:9003/allocation' \
  --data-urlencode 'window=24h' \
  --data-urlencode 'aggregate=label:team' \
  -G | jq '.data[0]'
```

→ 팀 별 비용.

## 7. Grafana 대시보드 import (선택)

OpenCost 는 Prometheus 메트릭으로도 노출 → Grafana 에서 시각화.

ID **9837** (OpenCost 공식 대시보드) import.

## 8. 정리

```bash
helm uninstall opencost -n opencost
kubectl delete ns opencost
```

## 학습 확인

- OpenCost 가 가격 정보를 어디서 가져오나?
- 같은 NS 의 여러 Deployment 비용을 분리해 보려면 어떤 aggregate?
- KubeCost 와 OpenCost 의 차이는?

다음: [quiz.md](./quiz.md)
