# Lab 02 — Burst! 메시지 1만 건 주입

## 1. 시작 시각 기록

```bash
START=$(date +%s)
echo "Start: $(date) (epoch=$START)"
```

## 2. SQS 에 1만 건 주입 (배치 송신)

SQS SendMessageBatch 는 한 번에 10건. 병렬로 빠르게:

```bash
SEND_BATCH() {
  local START=$1
  local COUNT=10
  ENTRIES=""
  for i in $(seq 0 $((COUNT-1))); do
    ID=$((START + i))
    ENTRIES="${ENTRIES} Id=msg-${ID},MessageBody=\"{\\\"order_id\\\":\\\"o-${ID}\\\",\\\"amount\\\":$((RANDOM%1000))}\""
  done
  aws sqs send-message-batch --queue-url $QUEUE_URL --entries $ENTRIES > /dev/null
}
export -f SEND_BATCH
export QUEUE_URL

# 1000 batch × 10 messages = 10000
seq 1 10000 10 | xargs -P 20 -I{} bash -c 'SEND_BATCH {}'

echo "Sent 10000 messages"
echo "Queue size:"
aws sqs get-queue-attributes --queue-url $QUEUE_URL \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
  --query 'Attributes' --output table
```

## 3. 관찰 시작

준비한 터미널 A/B/C 에서 진행 관찰.

### T+30s ~ T+60s: KEDA 가 Pod 늘리기 시작
**터미널 A**:
```
NAME                              STATUS    NODE
payment-service-xxx-aaa           Pending   <none>
payment-service-xxx-bbb           Pending   <none>
... (30개 모두 Pending)
```

### T+60s ~ T+120s: Karpenter 가 노드 추가
**터미널 B**:
```
NAME              STATUS    INSTANCE-TYPE   ZONE
ip-10-20-x-x...   Ready     m5a.xlarge      ap-northeast-2a    ← 새로!
ip-10-20-y-y...   Ready     m5.xlarge       ap-northeast-2b    ← 새로!
```

```bash
kubectl get nodeclaims
```
→ NodeClaim 진행 단계 (Launched → Registered → Initialized → Ready).

### T+120s ~: Pod 들 Running
**터미널 A**:
```
payment-service-xxx-aaa     Running   ip-10-20-x-x   1/1
payment-service-xxx-bbb     Running   ip-10-20-x-x   1/1
... (30개)
```

### T+120s ~ T+10min: 메시지 처리
**터미널 C**: 큐 길이 감소
```
ApproximateNumberOfMessages
8500
6200
3800
1100
0    ← 처리 완료
```

## 4. 처리 완료 시각 기록

```bash
END_PROCESS=$(date +%s)
DURATION=$((END_PROCESS - START))
echo "Processing completed: $(date)"
echo "Total duration: ${DURATION}s"
```

## 5. 큐 비고 cooldown 시작

```bash
sleep 100
```

**터미널 A**: Pod 0 으로 줄어듦.
**터미널 B**: 빈 노드 발생 → 30초 후 회수.

```bash
END_TEARDOWN=$(date +%s)
echo "Pods scaled to 0: $(date)"
```

## 6. 끝 — 완전 0 상태 복귀

```bash
sleep 30
kubectl get pods -n order -l app.kubernetes.io/name=payment-service
kubectl get nodes -l managed-by=karpenter
```

기대: Pod 0개, Karpenter 노드 0개 (또는 최소).

```bash
END_FINAL=$(date +%s)
TOTAL=$((END_FINAL - START))
echo "Total time from start to teardown: ${TOTAL}s ($(($TOTAL / 60)) min)"
```

## 7. 핵심 timing 기록

다음 lab 분석을 위해 기록:
| 시점 | 시간 |
|------|------|
| T0 — 메시지 주입 시작 | $(date) |
| T1 — 첫 Pod Running | ? |
| T2 — Karpenter 노드 Ready | ? |
| T3 — 큐 비음 | ${END_PROCESS}s |
| T4 — Pod 0 | ${END_TEARDOWN}s |
| T5 — Node 0 | ${END_FINAL}s |

다음: [lab-03-analysis.md](./lab-03-analysis.md)
