# Lab 01 — Spot 다양화 + On-Demand Fallback

## 학습 확인 포인트

- [ ] 두 NodePool (spot 우선 + ondemand fallback) 작동
- [ ] Karpenter 가 다양한 인스턴스 타입을 동시 고려
- [ ] AZ 분산 확인

## 1. 분리된 NodePool 적용

```bash
# 모듈 10 의 default NodePool 제거
kubectl delete nodepool default --ignore-not-found

# 새 NodePool 적용
kubectl apply -f manifests/nodepool-tiered.yaml
kubectl get nodepool
```

기대:
```
NAME       NODECLASS   NODES   READY   AGE
ondemand   default     0       True    10s
spot       default     0       True    10s
```

## 2. inflate Deployment 다시 사용 (모듈 10 의 manifest)

```bash
kubectl apply -f ../10-karpenter-install/manifests/inflate-deployment.yaml
kubectl scale deploy inflate --replicas=10
```

(`nodeSelector: managed-by: karpenter` → 두 NodePool 모두 매칭)

## 3. 노드 분포 확인

```bash
sleep 90
kubectl get nodes -L nodepool,topology.kubernetes.io/zone,node.kubernetes.io/instance-type \
  | grep karpenter
```

기대 (예시):
```
ip-10-20-1-x  spot       ap-northeast-2a  c5a.large
ip-10-20-2-y  spot       ap-northeast-2b  m6a.large
ip-10-20-3-z  spot       ap-northeast-2c  t3a.large
```

→ 다른 AZ + 다른 instance family 자동 분산.

## 4. Spot 가격 정보 확인

Karpenter 가 가격 데이터를 어떻게 가지고 있는지:
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50 \
  | grep -i 'price\|spot' | head -10
```

또는 가격 API 직접:
```bash
aws ec2 describe-spot-price-history \
  --instance-types c5.large c5a.large m5.large m6a.large \
  --product-descriptions "Linux/UNIX" \
  --start-time $(date -u -v-1H +%FT%TZ) \
  --query 'SpotPriceHistory[*].[InstanceType,AvailabilityZone,SpotPrice]' \
  --output table | head -20
```

## 5. On-Demand fallback 강제 시뮬레이션

Spot 만 가능한 상태에서 Spot 을 못 받게 하면 → On-Demand NodePool 로 fallback.

(실제로 Spot 부족을 만들기는 어렵지만, NodePool 의 weight 차이로 우선순위 확인 가능)

```bash
# spot NodePool 의 limits 를 0 으로 줄여 Spot 을 못 만들게 함
kubectl patch nodepool spot --type=merge -p '{"spec":{"limits":{"cpu":"0"}}}'

# 스케일 늘리기
kubectl scale deploy inflate --replicas=15
sleep 60

# 새 노드는 ondemand NodePool 에서
kubectl get nodes -L nodepool,capacity-type | grep karpenter
```

기대: 신규 노드의 `nodepool=ondemand`, `capacity-type=on-demand`.

원복:
```bash
kubectl patch nodepool spot --type=merge -p '{"spec":{"limits":{"cpu":"100"}}}'
```

## 6. 정리

```bash
kubectl scale deploy inflate --replicas=0
sleep 60
kubectl get nodes -L nodepool | grep karpenter      # 모두 회수되어 비어야 함
```

## 학습 확인 질문

1. `weight: 100` (spot) 과 `weight: 10` (ondemand) 의 효과는?
2. instance-family 를 `[c5, m5]` 만으로 제한하면 안정성에 어떤 영향?
3. AZ 별로 노드를 강제 분산하려면 NodePool 외에 어떤 K8s 기능을 같이 써야 하나? (힌트: topologySpreadConstraints)

다음: [lab-02-disruption.md](./lab-02-disruption.md)
