# Lab 03 — Grafana 대시보드 + Alert

## 학습 확인 포인트

- [ ] 외부 대시보드를 ID로 import
- [ ] PrometheusRule CRD 로 alert 정의
- [ ] Alertmanager 에서 active alert 확인

## 1. Grafana 외부 대시보드 import

Grafana UI (http://localhost:3000) → 좌측 + 메뉴 → Import.

추천 ID들:
- **315** — Kubernetes cluster monitoring
- **1860** — Node Exporter Full
- **7249** — Kubernetes Cluster (Prometheus)
- **6417** — Kubernetes Cluster (autoscaling 시각)
- **8588** — Kubernetes Deployment Statefulset Daemonset

각 ID 입력 → Load → Datasource: `Prometheus` 선택 → Import.

대시보드들이 자동으로 데이터 표시.

## 2. PrometheusRule 로 alert 정의

```bash
kubectl apply -f manifests/prometheusrule.yaml
kubectl get prometheusrule -n monitoring eks-study-app-rules
```

## 3. Prometheus UI 에서 rule 확인

http://localhost:9090/rules — 등록된 rule 그룹 목록.

## 4. CrashLoop alert 인위적으로 발생시키기

```bash
kubectl run crashloop --image=busybox -- sh -c "exit 1"
kubectl get pod crashloop --watch    # CrashLoopBackOff 로 진입
```

5분 정도 기다리기 (`for: 5m` 임계).

http://localhost:9090/alerts — `PodCrashLooping` 이 `Pending` → `Firing`.

## 5. Alertmanager UI

```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-alertmanager 9093:9093 &
```

브라우저: http://localhost:9093

활성 alert 가 보임 + 라우팅, 묵음(silence) 가능.

## 6. Alertmanager 라우팅 (Slack 예시)

(실제 Slack webhook이 있어야 동작 — 학습용 참고)

```bash
cat > /tmp/alertmanager-config.yaml <<'EOF'
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: eks-study-alerts
  namespace: monitoring
  labels:
    alertmanagerConfig: kps
spec:
  route:
    receiver: slack-warning
    groupBy: [namespace, alertname]
    routes:
      - matchers:
          - {name: severity, value: critical}
        receiver: slack-critical
  receivers:
    - name: slack-warning
      slackConfigs:
        - apiURL: <YOUR_SLACK_WEBHOOK_URL>
          channel: '#eks-warning'
          sendResolved: true
    - name: slack-critical
      slackConfigs:
        - apiURL: <YOUR_SLACK_WEBHOOK_URL>
          channel: '#eks-critical'
          sendResolved: true
EOF
```

> 실제 webhook 없으면 적용 안 함. 운영에서는 PagerDuty / Opsgenie 등.

## 7. Alert 정리

```bash
kubectl delete pod crashloop
kubectl delete prometheusrule -n monitoring eks-study-app-rules
```

## 8. 모듈 cleanup (Container Insights + kube-prometheus-stack)

```bash
# Prometheus stack
helm uninstall kps -n monitoring
kubectl delete pvc -n monitoring -l release=kps    # PV 정리
kubectl delete ns monitoring

# CloudWatch Container Insights addon
eksctl delete addon --name amazon-cloudwatch-observability --cluster eks-study --region ap-northeast-2

# CloudWatch Logs Group 삭제 (비용 정지)
for lg in $(aws logs describe-log-groups \
  --log-group-name-prefix /aws/containerinsights/eks-study/ \
  --query 'logGroups[].logGroupName' --output text); do
  aws logs delete-log-group --log-group-name "$lg"
done

kubectl delete ns amazon-cloudwatch --ignore-not-found
```

## 학습 확인 질문

1. PrometheusRule의 `for: 5m` 의 의미는?
2. Grafana 대시보드의 데이터는 어디서 오는가? (저장소 / 쿼리 메커니즘)
3. Alertmanager 가 Prometheus 와 분리된 이유는?

다음: [quiz.md](./quiz.md)
