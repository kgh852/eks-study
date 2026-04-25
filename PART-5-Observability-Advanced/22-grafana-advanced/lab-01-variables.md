# Lab 01 — Variables 활용

## 1. Grafana 접근

```bash
kubectl port-forward -n monitoring svc/kps-grafana 3000:80 &
```

http://localhost:3000 (admin / eks-study-admin)

## 2. 새 대시보드 생성

1. 좌측 + 메뉴 → Dashboard
2. New panel 추가 → close (변수 먼저 만들기)

## 3. 변수 정의

Settings (대시보드 우상단 톱니) → Variables → Add variable.

### 변수 1: namespace
- **Name**: namespace
- **Type**: Query
- **Data source**: Prometheus
- **Query**: `label_values(kube_pod_info, namespace)`
- **Multi-value**: ✓ (여러 NS 선택 가능)
- **Include All option**: ✓
- Apply

### 변수 2: pod
- **Name**: pod
- **Type**: Query
- **Query**: `label_values(kube_pod_info{namespace=~"$namespace"}, pod)`     ← cascading
- **Multi-value**: ✓
- Apply

### 변수 3: interval (rate window)
- **Name**: interval
- **Type**: Interval
- **Values**: `1m,5m,15m,1h`

## 4. 패널에서 변수 사용

새 패널 → Time series. Query:
```
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=~"$namespace",pod=~"$pod"}[$interval]))
```

상단 drop-down 으로 namespace / pod / interval 변경 시 그래프 즉시 갱신.

## 5. Repeat by variable (한 변수당 패널 자동 복제)

패널 설정 → Repeat options:
- Repeat by: `namespace`

→ 각 namespace 마다 같은 패널이 한 줄에 자동 생성.

## 6. 변수 export → JSON 저장

대시보드 Settings → JSON Model → 복사. 다음 lab 의 provisioning 에 사용.

## 7. 표준 대시보드 변수 (재사용 패턴)

| 변수 | Query | 용도 |
|------|-------|------|
| `cluster` | `label_values(kubernetes_cluster)` 또는 hardcode | 멀티 클러스터 |
| `namespace` | `label_values(kube_pod_info, namespace)` | NS 필터 |
| `pod` | `label_values(kube_pod_info{namespace=~"$namespace"}, pod)` | Pod 필터 |
| `instance` | `label_values(node_uname_info, instance)` | 노드 필터 |
| `interval` | Interval type | rate window |

## 8. 학습 확인

1. `Multi-value` 옵션 + `=~` regex 매칭 조합의 효과는?
2. `label_values` 와 `query_result` 함수의 차이는?
3. cascading 변수 ($namespace → $pod) 가 늦게 갱신되는 이유?

다음: [lab-02-provisioning.md](./lab-02-provisioning.md)
