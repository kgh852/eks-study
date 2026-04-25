# 이론 — EKS Upgrade Strategy

## 1. EKS 버전 정책

- 분기마다 새 마이너 버전 출시 (1.29, 1.30, 1.31, ...)
- 각 버전은 **Standard support 14개월** + Extended support 12개월 (유료)
- Extended 만료되면 자동 업그레이드 강제

→ **분기당 한 번 업그레이드 권장**. 6개월 미루면 곧 만료 위협.

## 2. 업그레이드 순서

```
1. Control Plane (1.30 → 1.31)
   ↓ (한 번에 한 마이너 버전만)
2. EKS Addon (vpc-cni, coredns, kube-proxy, ebs-csi)
   ↓
3. Managed Node Group (또는 Karpenter 가 자동)
   ↓
4. 워크로드 호환성 검증
```

**역순 X**: 노드를 1.31 로 먼저 올리면 1.30 Control Plane 과 호환 안 됨.

## 3. Skew Policy (Control Plane vs 노드)

- **kubelet** ≤ kube-apiserver (같거나 한 단계 낮음)
- 즉, Control Plane 1.31 이면 노드는 1.30 / 1.31 OK. 1.32 노드는 ❌.

## 4. 업그레이드 전 호환성 점검

### 4.1 Deprecated API 사용 여부

K8s 마이너 버전마다 일부 API 제거. 예: `policy/v1beta1` PodDisruptionBudget 은 1.25 에서 제거.

```bash
# pluto 도구 (deprecated API 검출)
pluto detect-helm --output wide
pluto detect-files -d ./manifests
```

또는 EKS 의 `EKS upgrade insights` (콘솔):
- Console → EKS → 클러스터 → Upgrade Insights
- API 사용 / addon 호환성 자동 점검

### 4.2 노드 OS / kubelet 버전

```bash
kubectl get nodes -o wide
# VERSION 컬럼 확인
```

### 4.3 Addon 호환

```bash
eksctl utils describe-addon-versions --kubernetes-version 1.31 --name vpc-cni
```

## 5. Control Plane 업그레이드

```bash
eksctl upgrade cluster --name eks-study --version 1.31 --approve
# 또는 Terraform: cluster_version 변수 변경 후 apply
# 또는 콘솔: Update version
```

소요: 약 20~30분. 무중단 (워크로드 영향 없음).

## 6. Addon 업그레이드

```bash
for addon in vpc-cni coredns kube-proxy aws-ebs-csi-driver; do
  LATEST=$(eksctl utils describe-addon-versions --kubernetes-version 1.31 --name $addon \
    --query 'Addons[0].AddonVersions[0].AddonVersion' --output text)
  eksctl update addon --name $addon --version $LATEST --cluster eks-study --force
done
```

## 7. 노드 그룹 업그레이드

### 7.1 Managed Node Group

```bash
eksctl upgrade nodegroup --cluster eks-study --name workers
```

- 새 launch template (최신 EKS-optimized AMI)
- ASG 가 점진적 surge → 새 노드 join → 옛 노드 cordon/drain → 종료
- 자동 PDB 존중

### 7.2 Karpenter 노드

Karpenter v1 부터 **Drift** 가 자동:
- EC2NodeClass 의 AMI alias 가 `al2023@latest` 면 새 AMI 출시 시 자동 drift
- Disruption Budget 따라 점진 회전

수동 트리거:
```bash
kubectl annotate nodes -l managed-by=karpenter karpenter.sh/disruption=Drifted=$(date +%s) --overwrite
```

### 7.3 Self-Managed (legacy)

Launch template 직접 변경 + ASG instance refresh. 권장 X (Managed 또는 Karpenter 로 마이그).

## 8. 워크로드 호환성 점검 (업그레이드 후)

```bash
# 모든 Pod Ready
kubectl get pods -A | grep -v Running | grep -v Completed

# 핵심 시스템 Pod 모두 Ready
kubectl get pods -n kube-system -o jsonpath='{range .items[*]}{.metadata.name}={.status.phase}{"\n"}{end}'

# Deprecated API 사용 흔적 (audit log)
aws logs filter-log-events \
  --log-group-name /aws/eks/eks-study/cluster \
  --filter-pattern '"requestObject" "extensions/v1beta1"' \
  --max-items 5
```

## 9. Blue/Green 업그레이드 패턴 (운영)

여러 마이너 점프 또는 위험한 업그레이드 시:
1. 새 클러스터 (1.32) Terraform 으로 별도 생성
2. 워크로드 배포
3. Route 53 weighted 로 점진 트래픽 이전
4. 옛 클러스터 (1.30) 삭제

**장점**: 즉시 롤백 가능, blast radius 격리.
**단점**: 2배 비용 (이행 동안), DNS 캐시 / 세션 관리 필요.

## 10. Karpenter + Drift 로 무중단 노드 업그레이드 (실무 best)

```yaml
# EC2NodeClass 의 amiFamily 변경 또는 alias 갱신
spec:
  amiFamily: AL2023
  amiSelectorTerms:
    - alias: al2023@latest    # ← 새 AMI 자동 채택
```

→ 모든 기존 노드 Drift → Karpenter 가 PDB / Budget 존중하며 점진 교체.

다음: [lab-01-prereq-check.md](./lab-01-prereq-check.md)
