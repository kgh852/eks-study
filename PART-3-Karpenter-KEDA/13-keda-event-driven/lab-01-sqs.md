# Lab 01 — SQS 기반 ScaledObject

## 학습 확인 포인트

- [ ] SQS 큐 만들고 KEDA Operator 에 SQS 읽기 권한 IRSA 부여
- [ ] payment-service 가 0 → N 으로 큐 길이에 비례 스케일
- [ ] 큐 비우면 다시 0

## 1. SQS 큐 생성

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2

aws sqs create-queue --queue-name eks-study-payments --region $REGION

QUEUE_URL=$(aws sqs get-queue-url --queue-name eks-study-payments --query QueueUrl --output text)
echo $QUEUE_URL
```

## 2. KEDA Operator 에 SQS 권한 IRSA

```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=keda \
  --name=keda-operator \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess \
  --override-existing-serviceaccounts \
  --approve --region=$REGION

# Pod 재시작 (SA annotation 새로 반영)
kubectl rollout restart deploy/keda-operator -n keda
kubectl wait --for=condition=available deploy/keda-operator -n keda
```

## 3. payment-service 의 SA 에 IRSA (Pod 도 SQS 호출 가능해야)

```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=order \
  --name=payment-service \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonSQSFullAccess \
  --override-existing-serviceaccounts \
  --approve --region=$REGION
```

## 4. payment-service Deployment 의 env 갱신 (실제 큐 URL 로)

```bash
kubectl set env deploy/payment-service -n order \
  SQS_QUEUE_URL=$QUEUE_URL \
  AWS_REGION=$REGION
```

`kubectl rollout status deploy/payment-service -n order` 로 새 Pod 가 떠 있는지 확인 (이전엔 placeholder URL 로 CrashLoop 였을 수 있음).

## 5. ScaledObject 적용

```bash
sed "s|ACCOUNT_ID|${ACCOUNT_ID}|g" manifests/sqs-scaledobject.yaml \
  | kubectl apply -f -

kubectl get scaledobject -n order
```

## 6. payment-service 가 0 으로 줄어드는 것 관찰

```bash
watch -n3 'kubectl get hpa -n order; kubectl get pods -n order -l app.kubernetes.io/name=payment-service'
```

기대 (1~2분 후 큐가 비어있으니):
```
HPA TARGETS         REPLICAS
... 0/5 (avg)       0      ← scale-to-zero
```

## 7. 큐에 메시지 1000건 주입 → Pod 폭발

```bash
echo "Sending messages..."
for i in $(seq 1 1000); do
  aws sqs send-message --queue-url $QUEUE_URL \
    --message-body "{\"order_id\":\"o-$i\",\"amount\":$((RANDOM % 1000))}" \
    > /dev/null &
  if (( i % 50 == 0 )); then wait; fi
done
wait
echo "Done."
```

watch 화면:
```
HPA TARGETS         REPLICAS
... 1000/5 (avg)    30     ← maxReplicaCount 도달
```

(1000/5 = 200 desired, max 30 으로 제한)

## 8. Pod 들이 메시지 처리

```bash
kubectl logs -n order -l app.kubernetes.io/name=payment-service --tail=20 --prefix=true
```

기대: 각 Pod 가 메시지 받아 "processed payment" 로그 남김.

큐 잔여량 모니터:
```bash
watch -n5 "aws sqs get-queue-attributes --queue-url $QUEUE_URL \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages' --output text"
```

처리되면서 0 으로 감소.

## 9. 처리 완료 후 자동 축소

큐가 비면 → KEDA cooldown 90초 후 → 0 으로.

## 10. 정리

```bash
kubectl delete -f manifests/sqs-scaledobject.yaml --ignore-not-found
aws sqs delete-queue --queue-url $QUEUE_URL
```

## 학습 확인 질문

1. KEDA Operator 의 IRSA 와 payment-service Pod 의 IRSA 가 별도인 이유는?
2. queueLength=5, max=30 일 때 큐에 100 메시지 있으면 desired Pod 수는?
3. SQS 의 `ApproximateNumberOfMessages` 는 정확한가?

다음: [lab-02-kafka.md](./lab-02-kafka.md)
