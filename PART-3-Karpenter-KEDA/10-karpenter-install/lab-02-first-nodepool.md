# Lab 02 — 첫 NodePool + 자동 노드 추가 시연

## 학습 확인 포인트

- [ ] NodePool/EC2NodeClass 적용 후 Karpenter 가 인식
- [ ] Pending Pod 발생 → Karpenter 가 노드 추가 → Pod 스케줄
- [ ] NodeClaim 객체로 노드 생성 진행 추적

## 1. NodePool + EC2NodeClass 적용

```bash
kubectl apply -f manifests/nodepool-default.yaml
kubectl get nodepool,ec2nodeclass
```

기대:
```
NAME                              NODECLASS   NODES   READY   AGE
nodepool.karpenter.sh/default     default     0       True    10s

NAME                                       READY   AGE
ec2nodeclass.karpenter.k8s.aws/default     True    10s
```

`READY: True` 가 안 되면 EC2NodeClass 의 `status.conditions` 확인:
```bash
kubectl describe ec2nodeclass default
```

흔한 원인: 서브넷/SG 태깅 누락 → status에 명시.

## 2. Watch 준비 (별도 터미널 3개)

터미널 A — 노드 변화:
```bash
watch -n2 kubectl get nodes -L karpenter.sh/nodepool,karpenter.sh/capacity-type,node.kubernetes.io/instance-type
```

터미널 B — Karpenter 로그:
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

터미널 C — NodeClaim:
```bash
watch -n2 kubectl get nodeclaims
```

## 3. inflate Deployment 적용 (replicas=0)

```bash
kubectl apply -f manifests/inflate-deployment.yaml
kubectl get deploy inflate
```

## 4. 스케일 업 → 노드 자동 추가

```bash
kubectl scale deploy inflate --replicas=5
kubectl get pods -l app=inflate
```

→ 즉시 5개 Pod 모두 Pending (요청 자원이 큼 + nodeSelector 가 Karpenter 노드 만 매칭).

터미널 A 에서 1~2분 후:
```
NAME                                              STATUS   ...   NODEPOOL    CAPACITY-TYPE
ip-10-20-x-x.ap-northeast-2.compute.internal     Ready    ...   <none>      ON_DEMAND        ← 기존 워커
ip-10-20-y-y.ap-northeast-2.compute.internal     Ready    ...   default     spot             ← Karpenter 가 추가!
```

터미널 B 의 Karpenter 로그:
```
INFO  computed new nodeclaim(s) to fit pod(s)
INFO  registered nodeclaim
INFO  initialized nodeclaim
INFO  inflate-xxx, ... scheduled
```

터미널 C:
```
NAME             TYPE         CAPACITY  ZONE              NODE                 READY   AGE
default-abcde    c5.large     spot      ap-northeast-2a   ip-10-20-y-y...     True    1m
```

## 5. Pod 들이 스케줄되었는지 확인

```bash
kubectl get pods -l app=inflate -o wide
```

기대: 모든 Pod 가 Running, Karpenter 노드에 떠 있음.

## 6. 더 늘려보기

```bash
kubectl scale deploy inflate --replicas=15
```

기대: 추가 노드 1~2 대 더 자동 생성. 인스턴스 타입은 Karpenter 가 비용/가용성 보고 선택 (c5.large / m5.large / m6a.large 등).

## 7. NodePool 의 limits 효과

```bash
kubectl describe nodepool default | grep -A3 'Limits\|Resources:'
```

`spec.limits.cpu: 100` 까지만 만듦. 그 이상 요청은 Pending 유지 (제한이 보호 장치).

## 8. 확인 명령 모음

```bash
# 현재 NodeClaims
kubectl get nodeclaims -o custom-columns=NAME:.metadata.name,TYPE:.spec.requirements,READY:.status.conditions[?(@.type=='Ready')].status

# Pod 분포
kubectl get pods -l app=inflate -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}' | column -t

# Karpenter 가 만든 EC2 인스턴스
aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/nodepool,Values=default" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,InstanceLifecycle,LaunchTime]' \
  --output table
```

## 학습 확인 질문

1. NodeClaim 이 Ready 가 되기까지 어떤 단계를 거치는가?
2. NodePool 의 `limits.cpu: 100` 이 의미하는 것은?
3. Pod 의 nodeSelector 가 NodePool 의 라벨과 안 맞으면 어떻게 되는가?

다음: [lab-03-consolidation.md](./lab-03-consolidation.md)
