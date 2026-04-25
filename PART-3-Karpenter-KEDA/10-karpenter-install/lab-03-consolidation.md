# Lab 03 — Consolidation (노드 자동 회수)

## 학습 확인 포인트

- [ ] Pod 줄이면 노드가 자동으로 회수됨을 확인
- [ ] `consolidationPolicy` 의 두 모드 차이 체험
- [ ] 노드 회수 시 Pod 가 다른 노드로 우아하게 이동하는 것을 봄

## 1. 현재 상태 확인 (lab-02 에서 inflate 가 떠 있다고 가정)

```bash
kubectl get nodes -L managed-by
kubectl get pods -l app=inflate
```

## 2. Pod 줄이기

```bash
kubectl scale deploy inflate --replicas=2
```

watch (별도 터미널):
```bash
watch -n2 'kubectl get nodes -L nodepool,managed-by; echo; kubectl get nodeclaims'
```

기대 (30초 후):
- Karpenter 가 빈 노드를 cordon (`SchedulingDisabled`)
- drain 시작 (Pod이 다른 노드로 이전)
- 노드 / NodeClaim 제거
- EC2 인스턴스 종료

`consolidateAfter: 30s` 설정 효과 — 30초 동안 underutilized 상태가 유지되면 회수.

## 3. 모두 0 으로 만들기

```bash
kubectl scale deploy inflate --replicas=0
```

→ Karpenter 노드 모두 회수. 약 1분 후 `kubectl get nodes` 에 기존 워커 노드만 남음.

## 4. consolidationPolicy 비교

### 4.1 WhenEmpty (보수적)
- 노드가 **완전히 빈** 경우만 회수
- 안전하지만 자원 낭비 가능

```bash
kubectl patch nodepool default --type=merge \
  -p '{"spec":{"disruption":{"consolidationPolicy":"WhenEmpty","consolidateAfter":"30s"}}}'
```

### 4.2 WhenEmptyOrUnderutilized (권장 / 본 lab 의 기본)
- 노드가 비거나, **사용률이 낮고 다른 노드로 이전 가능**할 때 회수
- 더 적극적인 비용 최적화

원복:
```bash
kubectl patch nodepool default --type=merge \
  -p '{"spec":{"disruption":{"consolidationPolicy":"WhenEmptyOrUnderutilized","consolidateAfter":"30s"}}}'
```

## 5. Underutilized Consolidation 시연

작은 Pod 여러 개를 다른 노드에 떠있는 상태로 만든 뒤, 그것을 한 노드로 몰아 정리하는 동작.

```bash
# 작은 Pod 6개 (각 0.2 CPU)
cat > /tmp/small.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: small
spec:
  replicas: 6
  selector: {matchLabels: {app: small}}
  template:
    metadata: {labels: {app: small}}
    spec:
      nodeSelector: {managed-by: karpenter}
      containers:
        - name: pause
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
          resources: {requests: {cpu: 200m, memory: 100Mi}}
EOF
kubectl apply -f /tmp/small.yaml
sleep 60
kubectl get pods -l app=small -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c
```

처음에는 여러 노드에 분산. 일정 시간 후 Karpenter 가 통합:
```bash
sleep 120
kubectl get pods -l app=small -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c
```

기대: Pod 들이 더 적은 노드 (가능하면 1개) 로 통합되고, 빈 노드는 회수.

## 6. PDB (PodDisruptionBudget) 으로 보호

운영에서는 회수 시 동시 다운 Pod 수를 제한:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: small-pdb
spec:
  minAvailable: 50%
  selector:
    matchLabels: {app: small}
```

→ Karpenter 회수 시에도 PDB 존중. 이 lab 에서는 적용하지 않지만 운영 필수.

## 7. 정리

```bash
kubectl delete deploy inflate small
kubectl delete -f /tmp/small.yaml --ignore-not-found
```

NodePool / EC2NodeClass 는 다음 모듈에서도 사용하므로 유지.

## 학습 확인 질문

1. `consolidateAfter` 의 시간 의미는 (회수 결정의 cool-down)?
2. PDB 가 `minAvailable: 100%` 이면 Consolidation 가능한가?
3. ON_DEMAND 노드와 Spot 노드를 Karpenter 가 동시에 운영할 수 있나? 어떻게 비율 조정?

다음: [quiz.md](./quiz.md)
