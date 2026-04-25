# Lab 02 — PVC + EBS

## ⚠️ 비용 주의

- EBS gp3 5GB 학습 1시간: 약 0.005 USD (무시 가능)
- **반드시 PVC 삭제 후 EBS 볼륨이 실제로 사라졌는지 확인** — 안 사라지면 매월 청구

## 학습 확인 포인트

- [ ] StorageClass + PVC 만으로 EBS가 자동 생성되는 걸 확인했다
- [ ] PVC 삭제 시 reclaimPolicy=Delete 면 EBS도 삭제되는 걸 봤다
- [ ] Pod 재시작 후에도 데이터가 보존되는 걸 확인했다

## 1. EBS CSI Driver 확인

```bash
kubectl get csidrivers ebs.csi.aws.com
kubectl get pods -n kube-system -l app=ebs-csi-controller
```

없으면 Part 2의 IRSA 셋업이 필요. 임시로:
```bash
eksctl create addon --cluster eks-study --name aws-ebs-csi-driver \
  --region ap-northeast-2 \
  --service-account-role-arn $(aws iam get-role --role-name AmazonEKS_EBS_CSI_DriverRole --query Role.Arn --output text)
```

(`AmazonEKS_EBS_CSI_DriverRole` 가 없으면 Part 2 진행 후 돌아오기)

## 2. StorageClass 적용

```bash
kubectl apply -f manifests/storageclass-gp3.yaml
kubectl get sc
```

기대:
```
NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      AGE
gp3 (default)   ebs.csi.aws.com         Delete          WaitForFirstConsumer   10s
gp2             kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   1d
```

EKS는 기본 `gp2` StorageClass를 가지고 있는데, 우리는 `gp3` 를 새 기본값으로.

## 3. PVC + Pod 적용

```bash
kubectl apply -f manifests/pvc-pod.yaml
kubectl get pvc
```

기대 (몇 초 후):
```
NAME   STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
data   Bound    pvc-abc123-...                             5Gi        RWO            gp3
```

`Pending` 에 머물러 있으면 → CSI Driver / IAM 문제, `kubectl describe pvc data` 의 Events 확인.

## 4. PV와 EBS 볼륨 ID 확인

```bash
kubectl get pv
kubectl get pv $(kubectl get pvc data -o jsonpath='{.spec.volumeName}') -o yaml \
  | yq '.spec.csi.volumeHandle'
```

기대: `vol-xxxxxxxxxxxxxxxxx` 형태. AWS 콘솔에서 검색하면 실제 EBS 볼륨이 보임.

```bash
EBS_ID=$(kubectl get pv $(kubectl get pvc data -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.csi.volumeHandle}')
aws ec2 describe-volumes --volume-ids $EBS_ID --query 'Volumes[].[VolumeId,Size,VolumeType,State]' --output table
```

## 5. Pod에서 데이터 쓰기

```bash
kubectl logs -f pvcdemo
```

기대: `Writing to PV at <시각>...` 로그가 1줄씩 추가.

```bash
kubectl exec pvcdemo -- ls -l /data
kubectl exec pvcdemo -- cat /data/log.txt
```

## 6. Pod 재시작 후 데이터 유지 확인

```bash
kubectl delete pod pvcdemo
# 같은 Pod manifest를 다시 적용 (PVC는 그대로)
kubectl apply -f manifests/pvc-pod.yaml
kubectl exec pvcdemo -- cat /data/log.txt   # 옛 데이터가 남아 있음 + 새 줄 추가
```

## 7. PVC 삭제 → EBS 자동 삭제 확인

```bash
kubectl delete -f manifests/pvc-pod.yaml
kubectl get pvc
```

PVC가 사라진 후:
```bash
sleep 30
aws ec2 describe-volumes --volume-ids $EBS_ID 2>&1 | head -5
```

기대: `InvalidVolume.NotFound` — EBS 볼륨이 실제로 삭제됨 (reclaimPolicy=Delete 효과).

## 8. WaitForFirstConsumer 의 의미

StorageClass의 `volumeBindingMode: WaitForFirstConsumer` 가 의미하는 것:
- PVC만 만들어선 PV/EBS 가 만들어지지 않음
- PVC를 사용하는 Pod가 실제 스케줄링되는 시점에야 생성
- Pod가 어느 AZ로 갈지 결정된 후, 같은 AZ에 EBS 생성 (EBS는 AZ 종속)

→ Multi-AZ 노드 그룹에서 자주 발생하는 "PVC가 다른 AZ의 EBS와 바인딩되어 Pod가 스케줄 못 됨" 문제 예방.

## 학습 확인 질문

1. accessModes 가 `ReadWriteOnce` 인 PVC를 두 Pod이 동시에 마운트하면 어떻게 되는가?
2. `volumeBindingMode: Immediate` 와 `WaitForFirstConsumer` 의 차이를 한 줄로?
3. `reclaimPolicy: Retain` 으로 만든 PV는 PVC 삭제 후 어떻게 정리해야 하는가?

다음: [lab-03-statefulset.md](./lab-03-statefulset.md)
