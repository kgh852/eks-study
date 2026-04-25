# Lab 02 — 노드 그룹 추가/삭제, 스케일링

## 학습 확인 포인트

- [ ] 두 번째 노드 그룹을 추가해 봤다 (다른 인스턴스 타입)
- [ ] 노드 그룹별 라벨/taint 사용
- [ ] 노드 그룹 스케일 (manual)

## 1. 현재 노드 그룹 확인

```bash
eksctl get nodegroup --cluster eks-study --region ap-northeast-2
kubectl get nodes -L workload-type
```

기대:
```
NAME      WORKLOAD-TYPE
ip-10-20-x-x   general
ip-10-20-y-y   general
```

(ClusterConfig에서 `labels: workload-type: general` 정의)

## 2. 라벨로 Pod 배치 강제

```bash
kubectl run pinned --image=nginx --overrides='{
  "spec": {
    "nodeSelector": {"workload-type": "general"}
  }
}'
kubectl get pod pinned -o wide
```

매칭되는 노드에 떠 있는지 확인 후 정리:
```bash
kubectl delete pod pinned
```

## 3. 두 번째 노드 그룹 추가 (CPU-intensive)

```bash
cat > /tmp/ng-cpu.yaml <<'EOF'
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: eks-study
  region: ap-northeast-2

managedNodeGroups:
  - name: cpu-workers
    instanceTypes: [c6a.large, c6i.large]
    spot: true
    desiredCapacity: 1
    minSize: 0
    maxSize: 3
    volumeSize: 30
    volumeType: gp3
    privateNetworking: true
    labels:
      workload-type: cpu
    taints:
      - key: workload
        value: cpu
        effect: NoSchedule
EOF

eksctl create nodegroup -f /tmp/ng-cpu.yaml
```

소요: 약 5분.

## 4. taint 효과 확인

```bash
kubectl run general-pod --image=nginx
kubectl get pod general-pod -o wide
```

기대: `general` 노드에만 떠 있음 (taint 없음). `cpu` 노드는 taint 때문에 회피.

## 5. toleration + nodeSelector 로 cpu 노드에 배치

```bash
cat > /tmp/cpu-pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: cpu-pod
spec:
  nodeSelector:
    workload-type: cpu
  tolerations:
    - key: workload
      operator: Equal
      value: cpu
      effect: NoSchedule
  containers:
    - name: nginx
      image: nginx
EOF
kubectl apply -f /tmp/cpu-pod.yaml
kubectl get pod cpu-pod -o wide
```

기대: `cpu-workers` 노드에 떠 있음.

```bash
kubectl delete pod general-pod cpu-pod
```

## 6. 스케일

```bash
eksctl scale nodegroup --cluster eks-study --name workers --nodes 3
kubectl get nodes -L workload-type
```

기대: general 노드 3개로 증가.

다시:
```bash
eksctl scale nodegroup --cluster eks-study --name workers --nodes 2
```

## 7. 노드 그룹 삭제 (cpu-workers는 더 이상 필요 없으므로)

```bash
eksctl delete nodegroup --cluster eks-study --name cpu-workers --region ap-northeast-2 --wait
```

## 학습 확인 질문

1. 노드 그룹별 IAM Role 이 분리되는 이유는? (보안 관점)
2. `spot: true` 인 노드 그룹의 Pod이 갑자기 종료될 때 어떻게 대응할 수 있을까?
3. taint와 toleration 만으로 Pod 배치를 강제할 수 있을까? nodeSelector도 같이 써야 하나?

다음: [lab-03-addons.md](./lab-03-addons.md)
