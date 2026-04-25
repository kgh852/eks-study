# Lab 02 — Provisioning (코드로 대시보드 관리)

## 1. kube-prometheus-stack 의 dashboard sidecar

이미 떠 있는 Grafana Pod 에는 sidecar 컨테이너가 있어, ConfigMap 에 `grafana_dashboard: "1"` 라벨을 자동 import 합니다.

```bash
kubectl get cm -n monitoring -l grafana_dashboard=1 | head
```

→ 기본으로 다수의 대시보드가 ConfigMap 으로 등록되어 있음.

## 2. 우리 대시보드 ConfigMap 적용

```bash
kubectl apply -f manifests/dashboard-msa.yaml
```

## 3. Grafana 에서 자동 import 확인

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard --tail=20
```

기대:
```
... POST request sent to http://localhost:3000/api/admin/provisioning/dashboards/reload (200, OK)
... Working on configmap monitoring/dashboard-msa-red
... File in configmap monitoring/dashboard-msa-red ADDED
```

Grafana UI → Dashboards → 검색 "MSA RED" → 대시보드 보임.

## 4. 대시보드 수정 → 재배포

ConfigMap 의 JSON 을 수정:
```bash
kubectl edit cm -n monitoring dashboard-msa-red
# panels 추가 / 수정
```

→ sidecar 가 자동 reload (수십 초 내).

## 5. 대시보드를 git 으로 관리하는 패턴

권장 구조:
```
manifests/
├── dashboards/
│   ├── msa-red.json
│   └── cluster-overview.json
└── dashboards-cm.yaml      # ConfigMap (data 가 위 .json 들)
```

ConfigMap 만드는 법:
```bash
kubectl create configmap dashboards -n monitoring \
  --from-file=manifests/dashboards/ \
  --dry-run=client -o yaml \
  | yq '.metadata.labels.grafana_dashboard = "1"' \
  > manifests/dashboards-cm.yaml
```

또는 Helm 차트의 `dashboards` values 활용 (kube-prometheus-stack 자체가 지원).

## 6. Datasource Provisioning

위 sidecar 와 비슷한 방식으로 datasource 도:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: extra-datasources
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
      - name: CloudWatch
        type: cloudwatch
        jsonData:
          authType: default
          defaultRegion: ap-northeast-2
```

## 7. Dashboard JSON 의 핵심 필드

```json
{
  "title": "...",
  "uid": "msa-red",          ← 영구 ID (대시보드 URL의 영구 부분)
  "tags": [...],
  "templating": {
    "list": [variables...]
  },
  "panels": [
    {
      "id": 1,
      "type": "timeseries",  // 또는 stat, gauge, table, ...
      "gridPos": {"x":0, "y":0, "w":12, "h":8},
      "targets": [{ "expr": "PromQL", "legendFormat": "{{label}}" }],
      "fieldConfig": {"defaults": {"unit": "...", "thresholds": ...}}
    }
  ]
}
```

## 8. 정리

```bash
kubectl delete -f manifests/dashboard-msa.yaml
```

## 학습 확인

1. `grafana_dashboard: "1"` 라벨이 없는 ConfigMap 은 어떻게 되는가?
2. ConfigMap 의 JSON 파일이 1MB 초과면? (K8s ConfigMap 한계)
3. provisioning vs UI 직접 만들기 의 트레이드오프?

다음: [lab-03-alerting.md](./lab-03-alerting.md)
