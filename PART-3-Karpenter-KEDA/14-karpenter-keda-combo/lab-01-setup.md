# Lab 01 — 시나리오 셋업

## 1. 사전 점검

```bash
# Karpenter
kubectl get nodepool

# KEDA
kubectl get pods -n keda
kubectl get scaledobject -n order

# payment-service IRSA
kubectl get sa -n order payment-service -o yaml | yq '.metadata.annotations'

# SQS 큐
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
QUEUE_URL=$(aws sqs get-queue-url --queue-name eks-study-payments --query QueueUrl --output text)
echo $QUEUE_URL
```

## 2. payment-service 의 리소스 명확화

```bash
sed "s|ACCOUNT_ID|${ACCOUNT_ID}|g; s|SQS_URL|${QUEUE_URL}|g" \
  manifests/payment-with-resources.yaml | kubectl apply -f -
```

(이미 모듈 13 에서 비슷한 spec 으로 떠 있을 가능성. 위 명령은 update.)

## 3. ScaledObject 가 큐 모니터링 중 확인

```bash
kubectl describe scaledobject -n order payment-service
```

기대: `Active: True` (또는 큐 비어있으면 False — 정상).

## 4. 노드 / Pod 베이스라인 캡처

```bash
echo "=== Baseline @ $(date) ==="
echo "Pods:"
kubectl get pods -n order -l app.kubernetes.io/name=payment-service
echo "Nodes (Karpenter):"
kubectl get nodes -l managed-by=karpenter -o wide
```

기대: payment-service Pod 0 개, Karpenter 노드 0 또는 최소.

## 5. Watch 터미널 준비 (3개)

**터미널 A — Pod**:
```bash
watch -n2 'kubectl get pods -n order -l app.kubernetes.io/name=payment-service -o wide'
```

**터미널 B — 노드**:
```bash
watch -n2 'kubectl get nodes -l managed-by=karpenter -L node.kubernetes.io/instance-type,topology.kubernetes.io/zone'
```

**터미널 C — 큐 길이**:
```bash
watch -n5 "aws sqs get-queue-attributes --queue-url $QUEUE_URL \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages' --output text"
```

## 6. (선택) Grafana 열기

```bash
kubectl port-forward -n monitoring svc/kps-grafana 3000:80 &
```

→ http://localhost:3000 → Dashboards → "Kubernetes / Compute Resources / Namespace (Pods)" → namespace=order.

준비 완료. 다음: [lab-02-burst.md](./lab-02-burst.md)
