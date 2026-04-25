# 시나리오 7 — PVC stuck Pending

## 1. 재현

존재하지 않는 StorageClass 로 PVC 만들기:
```bash
cat > /tmp/bad-pvc.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: bad-pvc
spec:
  storageClassName: nonexistent-sc
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
EOF
kubectl apply -f /tmp/bad-pvc.yaml
sleep 10
```

## 2. 증상

```bash
kubectl get pvc bad-pvc
```

```
NAME      STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
bad-pvc   Pending   ...                                 nonexistent-sc
```

## 3. 진단

### 3.1 PVC describe

```bash
kubectl describe pvc bad-pvc
```

기대 (Events):
```
storageclass.storage.k8s.io "nonexistent-sc" not found
```

### 3.2 사용 가능한 StorageClass 확인

```bash
kubectl get sc
```

기대:
```
NAME           PROVISIONER             RECLAIMPOLICY   ...
gp3 (default)  ebs.csi.aws.com         Delete          ...
gp2            kubernetes.io/aws-ebs   Delete          ...
```

### 3.3 다른 흔한 원인

| Events 메시지 | 원인 |
|---------------|------|
| `storageclass not found` | StorageClass 오타 / 미설치 |
| `waiting for first consumer` | Pod이 PVC 를 마운트해야 PV 가 만들어짐 (정상, 혹은 Pod Pending) |
| `failed to provision volume: ... AccessDenied` | EBS CSI Driver 의 IRSA 권한 부족 |
| `volume node affinity conflict` | PV 가 다른 AZ 에 있어 Pod 노드와 매칭 안 됨 |

## 4. 해결

```bash
# StorageClass 수정
kubectl patch pvc bad-pvc --type=merge -p '{"spec":{"storageClassName":"gp3"}}'
# 안 됨: spec 의 일부는 immutable

# 깔끔한 방법: PVC 삭제 후 재생성
kubectl delete pvc bad-pvc
sed 's/nonexistent-sc/gp3/' /tmp/bad-pvc.yaml | kubectl apply -f -
sleep 10
kubectl get pvc bad-pvc
```

기대: `Bound`.

## 5. EBS CSI IRSA 문제 진단

PVC 가 만들어졌는데 EBS 자체가 안 생기면:
```bash
kubectl logs -n kube-system -l app=ebs-csi-controller -c csi-provisioner --tail=30
```

`AccessDenied` 면 IRSA 점검:
```bash
kubectl get sa -n kube-system ebs-csi-controller-sa -o yaml | yq '.metadata.annotations'
```

## 6. WaitForFirstConsumer 시 Pod Pending 과 PVC Pending 의 chicken-and-egg

```bash
# PVC + Pod 함께
cat > /tmp/wait-pvc.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: wait-data}
spec:
  storageClassName: gp3
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 1Gi}}
---
apiVersion: v1
kind: Pod
metadata: {name: wait-pod}
spec:
  nodeSelector: {bogus: bogus}      # 매칭 노드 없음 → Pod Pending
  containers:
    - name: c
      image: alpine
      command: ["sleep","3600"]
      volumeMounts: [{name: data, mountPath: /data}]
  volumes:
    - name: data
      persistentVolumeClaim: {claimName: wait-data}
EOF
kubectl apply -f /tmp/wait-pvc.yaml
sleep 15
kubectl get pvc wait-data
kubectl describe pod wait-pod | tail -10
```

기대:
- Pod: `FailedScheduling` (nodeSelector 미매칭)
- PVC: `Pending` — `waiting for first consumer` (Pod이 안 떠서)

→ Pod 의 진짜 문제 해결해야 PVC 도 풀림.

```bash
kubectl delete -f /tmp/wait-pvc.yaml
```

## 7. 정리

```bash
kubectl delete pvc bad-pvc --ignore-not-found
```

## 학습 확인

- `WaitForFirstConsumer` 모드의 의도는?
- PV 의 `nodeAffinity` 와 Pod 의 위치가 안 맞으면 어떤 메시지?
- EBS CSI IRSA 의 K8s SA 이름은?
