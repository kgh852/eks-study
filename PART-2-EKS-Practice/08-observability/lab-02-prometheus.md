# Lab 02 — kube-prometheus-stack 설치

## 학습 확인 포인트

- [ ] Prometheus + Grafana + Alertmanager 가 한 번에 설치됨을 봤다
- [ ] ServiceMonitor CRD 로 scrape 대상이 자동 등록됨
- [ ] Grafana 에서 클러스터 메트릭 시각화

## 1. Helm repo 추가

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

## 2. 설치

```bash
helm install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f manifests/values-prometheus.yaml \
  --version 65.x.x        # 본 lab 시점 stable
```

> 정확한 버전은 `helm search repo prometheus-community/kube-prometheus-stack -l | head` 로 확인

```bash
kubectl get pods -n monitoring --watch
```

5~7분 후:
```
NAME                                                     READY  STATUS
alertmanager-kps-kube-prometheus-stack-alertmanager-0   2/2    Running
kps-grafana-xxxxx                                       3/3    Running
kps-kube-prometheus-stack-operator-xxxxx                1/1    Running
kps-kube-state-metrics-xxxxx                            1/1    Running
kps-prometheus-node-exporter-xxxxx                      1/1    Running
prometheus-kps-kube-prometheus-stack-prometheus-0       2/2    Running
```

## 3. CRD 확인

```bash
kubectl get crd | grep monitoring.coreos.com
```

기대:
```
alertmanagers, podmonitors, probes, prometheuses, prometheusrules,
servicemonitors, thanosrulers
```

자동 생성된 ServiceMonitor 들:
```bash
kubectl get servicemonitor -n monitoring
```

## 4. Grafana 접근

```bash
kubectl port-forward -n monitoring svc/kps-grafana 3000:80 &
```

브라우저: http://localhost:3000
- ID: `admin`
- PW: `eks-study-admin`

좌측 → Dashboards 메뉴에 자동으로 import 된 대시보드 다수 (`Kubernetes / Compute Resources / *`).

## 5. Prometheus UI

```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
```

브라우저: http://localhost:9090

쿼리 시도:
```
# 노드 수
count(kube_node_info)

# Pod 수 (네임스페이스별)
sum(kube_pod_info) by (namespace)

# CPU 사용률
sum(rate(container_cpu_usage_seconds_total{namespace="default"}[1m])) by (pod)

# Active alerts
ALERTS{alertstate="firing"}
```

## 6. ServiceMonitor 직접 만들기 (커스텀 앱 메트릭)

본 커리큘럼의 `order-service` 가 `:9090/metrics` 를 노출함. 그것을 Prometheus가 scrape 하도록:

```bash
# (Part 1 미니 프로젝트의 차트 사용. 데모로 임시 배포)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
helm install order-svc \
  ../../PART-1-Kubernetes-Basics/04-rbac-helm/charts/order-service \
  --set image.repository=${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/eks-study/order-service \
  --set image.tag=latest \
  -n monitoring

# ServiceMonitor 추가
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: order-service
  namespace: monitoring
  labels:
    release: kps    # ← 이 label 이 있어야 prometheus 가 scrape
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: order-service
  endpoints:
    - port: metrics
      path: /metrics
      interval: 15s
EOF

# Prometheus targets 페이지에서 추가됨
# http://localhost:9090/targets → "serviceMonitor/monitoring/order-service" 검색
```

## 7. 정리 (이 lab의 데모만)

```bash
kubectl delete servicemonitor -n monitoring order-service
helm uninstall order-svc -n monitoring
```

(kube-prometheus-stack 자체는 다음 lab 에서 사용. 모듈 끝에 cleanup.)

## 학습 확인 질문

1. ServiceMonitor 의 `release: kps` 라벨이 왜 필요한가?
2. Prometheus 의 `retention: 1d` 의 트레이드오프는?
3. PromQL `rate(...)` 와 `irate(...)` 의 차이는?

다음: [lab-03-grafana-alert.md](./lab-03-grafana-alert.md)
