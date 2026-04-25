# 시나리오 3 — Pod Pending

## 1. 재현

지나치게 큰 자원 요청:
```bash
kubectl run hog --image=nginx --requests=cpu=100,memory=100Gi
sleep 15
```

## 2. 증상

```bash
kubectl get pod hog
```

```
NAME   READY   STATUS    RESTARTS   AGE
hog    0/1     Pending   0          15s
```

## 3. 진단

```bash
kubectl describe pod hog | tail -15
```

기대 (Events):
```
FailedScheduling: 0/3 nodes are available: 3 Insufficient cpu, 3 Insufficient memory
```

## 4. 원인 매핑

| Events 메시지 | 원인 |
|---------------|------|
| `Insufficient cpu/memory` | 노드 자원 부족 (또는 requests 과다) |
| `node(s) didn't match Pod's node affinity` | nodeSelector / affinity 매칭 실패 |
| `Too many pods` | 노드의 Pod 한계 (VPC CNI IP 한계) |
| `had untolerated taint` | taint 에 toleration 없음 |
| `pvc ... not found` | PVC 가 존재 안 함 (또는 PV 바인딩 실패) |

## 5. 진단 추가 명령

```bash
# 클러스터 전체 자원 vs 사용
kubectl describe nodes | grep -A5 'Allocated resources:'

# 노드별 라벨
kubectl get nodes --show-labels

# PV/PVC 상태
kubectl get pv,pvc -A
```

## 6. 해결

```bash
kubectl delete pod hog
```

운영에선:
- requests 줄이기 (실제 측정값 기반)
- Karpenter / 노드 그룹 capacity 늘리기
- nodeSelector 조정

## 7. Karpenter 가 떠있다면 어떻게 다른가

Karpenter 가 있으면 `Insufficient cpu` 에 대해 자동으로 노드 추가 시도. 그래도 NodePool 의 `limits` 또는 EC2 SVQ (Service Quota) 한계에 걸리면 Pending 유지. Karpenter 컨트롤러 로그 확인:

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50 \
  | grep -i 'unschedulable\|insufficient\|error'
```

## 학습 확인

- requests 와 limits 중 스케줄링에 사용되는 것은?
- 노드 자원이 충분한데도 Pending 인 케이스는?
- VPC CNI 의 Pod IP 한계로 Pending 인지 어떻게 알 수 있나?
