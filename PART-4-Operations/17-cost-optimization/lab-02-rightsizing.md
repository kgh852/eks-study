# Lab 02 — Right-Sizing (Container Insights + VPA)

## 1. 사용률 분석 (Container Insights / Prometheus)

### Prometheus 쿼리들

CPU 사용률 vs requests:
```
sum(rate(container_cpu_usage_seconds_total{namespace="order"}[5m])) by (pod, container)
  / sum(kube_pod_container_resource_requests{namespace="order",resource="cpu"}) by (pod, container)
```

기대: 0.0 ~ 1.0+ 의 비율. **0.5 미만이면 over-provisioning**.

메모리:
```
sum(container_memory_working_set_bytes{namespace="order"}) by (pod, container)
  / sum(kube_pod_container_resource_requests{namespace="order",resource="memory"}) by (pod, container)
```

### Container Insights (CloudWatch)

CloudWatch → Container Insights → Resources → Performance.
- Pod 별 CPU / Memory utilization
- 여러 시점의 평균 / max 비교

## 2. VPA 설치 (학습용 — 추천 모드)

```bash
git clone --depth=1 https://github.com/kubernetes/autoscaler.git /tmp/autoscaler
cd /tmp/autoscaler/vertical-pod-autoscaler

./hack/vpa-up.sh
kubectl get pods -n kube-system -l app=vpa-recommender
```

또는 Helm:
```bash
helm repo add fairwinds https://charts.fairwinds.com/stable
helm install vpa fairwinds/vpa -n vpa --create-namespace
```

## 3. VPA 적용 (order-service 대상)

```bash
cat > /tmp/vpa.yaml <<'EOF'
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: order-service
  namespace: order
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: order-service
  updatePolicy:
    updateMode: "Off"     # 추천만
  resourcePolicy:
    containerPolicies:
      - containerName: '*'
        controlledResources: ["cpu", "memory"]
        minAllowed: { cpu: 50m, memory: 64Mi }
        maxAllowed: { cpu: 1, memory: 1Gi }
EOF
kubectl apply -f /tmp/vpa.yaml
```

## 4. 부하 발생 + 데이터 수집 (15~30분)

```bash
# Module 14 의 부하 발생기 활용
ALB_DNS=$(kubectl get ingress -n order msa -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
kubectl run loadgen --image=alpine -n order --restart=Always \
  --overrides='{"spec":{"containers":[{"name":"loadgen","image":"alpine:3.19","command":["sh","-c"],"args":["apk add -q curl && while true; do curl -s -X POST http://'$ALB_DNS'/api/orders -H Content-Type:application/json -d {\"user_id\":\"u1\",\"amount\":1} > /dev/null; sleep 0.1; done"]}]}}'

sleep 1200    # 20분 데이터 수집
```

## 5. VPA 추천 확인

```bash
kubectl describe vpa -n order order-service
```

기대 (`Status` 섹션):
```
Status:
  Recommendation:
    Container Recommendations:
      Container Name:  app
      Lower Bound:
        Cpu:     20m
        Memory:  50Mi
      Target:                  ← 권장값
        Cpu:     85m
        Memory:  120Mi
      Upper Bound:
        Cpu:     200m
        Memory:  200Mi
```

`Target` 이 VPA 의 권장 requests. 현재 `100m / 128Mi` 와 비교:
- CPU: 100m → 85m (15% 감소 가능)
- Memory: 128Mi → 120Mi (소폭)

## 6. 적용 옵션

### 옵션 A — 수동 적용
```bash
kubectl patch deploy order-service -n order --type=merge -p '
{"spec":{"template":{"spec":{"containers":[
  {"name":"app","resources":{"requests":{"cpu":"85m","memory":"120Mi"}}}
]}}}}'
```

### 옵션 B — VPA Auto 모드
```bash
kubectl patch vpa order-service -n order --type=merge -p '{"spec":{"updatePolicy":{"updateMode":"Auto"}}}'
```

→ VPA 가 Pod 재시작하며 자동 패치. 운영에서는 신중하게 (Pod 재시작 주의).

## 7. HPA 와 충돌 회피

HPA 가 같은 Pod 의 CPU 로 수평 스케일 + VPA 가 CPU requests 로 수직 → 충돌.

**해결책**:
- VPA 는 Memory 만, HPA 는 CPU
- 또는 VPA 의 `updateMode: Off` 로 추천만, 사람이 검토 후 적용

## 8. 정리

```bash
kubectl delete pod -n order loadgen
kubectl delete vpa -n order order-service
```

## 학습 확인

- Right-sizing 의 목표 utilization 비율은 (이상적)?
- VPA Auto 모드의 위험은?
- HPA + VPA 같이 쓰는 패턴은?

다음: [lab-03-opencost.md](./lab-03-opencost.md)
