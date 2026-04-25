# 시나리오 6 — 노드 NotReady

## 1. 증상 (실제 발생 시)

```bash
kubectl get nodes
```

```
NAME              STATUS     ROLES    AGE   VERSION
ip-10-20-x-x...   NotReady   <none>   1d    v1.30.x
ip-10-20-y-y...   Ready      <none>   1d    v1.30.x
```

## 2. 진단

### 2.1 노드 describe

```bash
kubectl describe node ip-10-20-x-x...
```

`Conditions` 섹션 주목:
```
Type             Status  Reason
Ready            False   KubeletNotReady
MemoryPressure   False
DiskPressure     False
PIDPressure      False
NetworkUnavailable False
```

`Ready: False, Reason: KubeletNotReady` → kubelet 자체 문제.

### 2.2 시스템 Pod 상태

```bash
# CNI / kube-proxy
kubectl get pods -n kube-system -o wide --field-selector spec.nodeName=ip-10-20-x-x...
```

만약 `aws-node` (VPC CNI) 가 Pending 또는 CrashLoop 면 → 노드의 네트워크 셋업 실패 → kubelet 이 NotReady 보고.

### 2.3 kubelet 로그 (EC2 콘솔)

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=private-dns-name,Values=ip-10-20-x-x..." \
  --query 'Reservations[].Instances[].InstanceId' --output text)

aws ec2 get-console-output --instance-id $INSTANCE_ID --output text | tail -100
```

또는 SSM Session Manager 로 노드에 접근:
```bash
aws ssm start-session --target $INSTANCE_ID
# 안에서:
sudo journalctl -u kubelet -n 200 --no-pager
```

## 3. 흔한 원인 매핑

| Reason / 메시지 | 원인 |
|-----------------|------|
| `KubeletNotReady` + CNI Pod down | VPC CNI 문제 (IRSA, IP 부족) |
| `disk-pressure` | 노드 디스크 가득 (`/var/lib/containerd` 등) |
| `memory-pressure` | 노드 메모리 가득 |
| `OutOfDisk` | 옛 K8s 의 disk-pressure |
| `NetworkUnavailable` | NAT/Routing 문제 |
| 노드 자체 보임 안 함 (NotReady 30분+) | kubelet stuck → 노드 재기동 권장 |

## 4. 해결 — 자주 쓰는 패턴

### 4.1 Pod 빼내기 (cordon + drain)

```bash
kubectl cordon ip-10-20-x-x...
kubectl drain ip-10-20-x-x... --ignore-daemonsets --delete-emptydir-data
```

→ 정상 노드로 Pod 들이 옮겨짐.

### 4.2 노드 종료 후 재생성

Managed Node Group 의 경우 인스턴스 종료 → ASG 가 새 인스턴스 자동 생성:
```bash
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
```

Karpenter 가 만든 노드:
```bash
kubectl delete nodeclaim <claim-name>
```

### 4.3 디스크 가득 시

`/var/lib/docker` 또는 `/var/lib/containerd` 가 가득. 이미지 정리:
```bash
# 노드 SSH 후
sudo crictl rmi --prune
```

또는 `imageGCHighThresholdPercent` 를 kubelet config 에 낮게 설정 (자동 정리 트리거 빠르게).

## 5. 예방

- 모니터링: CloudWatch / Prometheus 의 노드 health (NotReady 알람)
- Karpenter 의 `expireAfter` 로 주기적 노드 회전
- 노드 디스크 사이즈 충분히 (gp3 30Gi 이상)

## 학습 확인

- `kubectl drain` 의 `--ignore-daemonsets` 가 필요한 이유는?
- DaemonSet Pod 는 drain 으로 못 내보낸다. 그럼 어떻게 정리?
- 노드가 NotReady 인 동안 그 노드의 Pod 들의 `STATUS` 는?
