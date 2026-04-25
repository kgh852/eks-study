# Lab 01 — VPC CNI 동작 관찰

## 학습 확인 포인트

- [ ] Pod IP가 노드의 ENI에 등록된 보조 IP임을 확인했다
- [ ] Pod 수와 노드의 ENI/IP 한계 관계를 안다
- [ ] aws-node DaemonSet 의 환경변수 의미를 안다

## 1. 노드와 ENI 매핑

```bash
kubectl get nodes -o wide
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=private-dns-name,Values=$NODE" \
  --query 'Reservations[].Instances[].InstanceId' --output text)

# 노드의 ENI들
aws ec2 describe-network-interfaces \
  --filters "Name=attachment.instance-id,Values=$INSTANCE_ID" \
  --query 'NetworkInterfaces[].[NetworkInterfaceId,PrivateIpAddress,PrivateIpAddresses[*].PrivateIpAddress]' \
  --output table
```

기대: ENI 한 개당 여러 IP (Primary + Secondary 들).

## 2. 그 노드의 Pod 들 IP 확인

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=$NODE | head -10
```

기대: 각 Pod IP가 위에서 본 ENI Secondary IP 중 하나와 일치.

## 3. aws-node DaemonSet (VPC CNI 자체)

```bash
kubectl describe ds aws-node -n kube-system | grep -A30 'Environment:' | head -40
```

기대 환경변수 (주요):
```
WARM_ENI_TARGET=1
WARM_IP_TARGET=...
MINIMUM_IP_TARGET=...
ENABLE_PREFIX_DELEGATION=false
```

## 4. Pod 한계 시뮬레이션

t3.medium 기준 노드별 Pod 최대치는 약 17 (시스템 Pod 포함, prefix delegation 없음).

```bash
# Deployment를 조금씩 늘리면서 확인
kubectl create deploy stress --image=pause:3.9 --replicas=15
kubectl rollout status deploy/stress
kubectl get pods -l app=stress -o wide | awk '{print $7}' | sort | uniq -c
# → 노드별 Pod 분포

# 더 늘려보기
kubectl scale deploy/stress --replicas=40
sleep 30
kubectl get pods -l app=stress | grep -c Running
kubectl get pods -l app=stress | grep -c Pending
```

기대: 일정 수에서 Pending 발생 (`FailedScheduling: too many pods` 또는 IP 부족).

확인:
```bash
kubectl describe pod $(kubectl get pods -l app=stress --field-selector status.phase=Pending -o name | head -1) | tail -10
```

```bash
kubectl delete deploy stress
```

## 5. Prefix Delegation 활성화 (학습용)

```bash
# 환경변수 활성화
kubectl set env ds/aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true

# 재시작 (DaemonSet)
kubectl rollout restart ds/aws-node -n kube-system
kubectl rollout status ds/aws-node -n kube-system
```

이제 Pod 한계가 훨씬 커집니다 (이론적으로 t3.medium ~110 Pod).

원복:
```bash
kubectl set env ds/aws-node -n kube-system ENABLE_PREFIX_DELEGATION=false
kubectl rollout restart ds/aws-node -n kube-system
```

## 6. 보조 IP 풀 모니터

```bash
kubectl get nodes -o json | jq '.items[].status.allocatable.pods'
```

각 노드의 K8s 가 보고하는 Pod 수용량 (위 환경변수에 따라 변함).

## 학습 확인 질문

1. AWS VPC CNI 가 만드는 Pod IP 는 K8s 의 가상 IP 인가, AWS VPC IP 인가?
2. `WARM_IP_TARGET=10` 으로 설정하면 어떤 효과?
3. Prefix Delegation 활성화의 트레이드오프는?

다음: [lab-02-alb-controller.md](./lab-02-alb-controller.md)
