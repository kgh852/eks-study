# Lab 03 — Addon + 노드 그룹 업그레이드

## 1. Addon 업그레이드

```bash
TARGET=1.31

for addon in vpc-cni coredns kube-proxy aws-ebs-csi-driver; do
  LATEST=$(eksctl utils describe-addon-versions --kubernetes-version $TARGET --name $addon \
    --query 'Addons[0].AddonVersions[0].AddonVersion' --output text)
  echo "→ Updating $addon to $LATEST"
  eksctl update addon --name $addon --version $LATEST --cluster eks-study \
    --region ap-northeast-2 --force
done
```

각 addon 약 1~2분 소요. coredns / kube-proxy 가 DaemonSet/Deployment 라 점진 갱신.

## 2. addon 업그레이드 검증

```bash
eksctl get addon --cluster eks-study
```

기대: 모든 addon `STATUS: ACTIVE`, version 이 새것.

```bash
# 시스템 Pod 들 모두 Ready
kubectl get pods -n kube-system | grep -vE 'Running|Completed'
```

## 3. 노드 그룹 업그레이드

### 3.1 Managed Node Group

```bash
eksctl upgrade nodegroup --cluster eks-study --name workers
# 또는 콘솔: 노드 그룹 → Update version
```

진행:
- 새 launch template 생성 (최신 EKS-optimized AMI 1.31)
- ASG surge: 새 노드 추가
- 옛 노드 cordon / drain
- 옛 인스턴스 종료

watch:
```bash
watch -n5 'kubectl get nodes -o jsonpath="{range .items[*]}{.metadata.name}={.status.nodeInfo.kubeletVersion}{\"\n\"}{end}"'
```

기대: 점진적으로 v1.31.x 로 교체.

소요: 노드 수 × 약 5분.

### 3.2 Karpenter 노드 (만약 떠있으면)

EC2NodeClass 의 amiFamily 가 `AL2023` + alias `al2023@latest` 면 자동 Drift 발생.

수동 트리거:
```bash
# AMI alias 업데이트 (예시)
kubectl patch ec2nodeclass default --type=merge -p '{"spec":{"amiSelectorTerms":[{"alias":"al2023@latest"}]}}'
# (이미 latest 면 변화 없음)
```

또는 강제:
```bash
# 모든 Karpenter 노드 drift 마크
kubectl annotate nodes -l managed-by=karpenter karpenter.sh/disruption-=
```

watch:
```bash
watch -n5 'kubectl get nodeclaims -L karpenter.sh/drifted'
```

## 4. PDB 영향 확인

업그레이드 중 PDB 가 막아 stuck 되면:
```bash
kubectl get pods -A -o jsonpath='{range .items[?(@.status.phase!="Running")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
```

stuck Pod 의 PDB 확인 + 임시 완화.

## 5. 업그레이드 후 통합 검증

```bash
# 모든 노드 새 버전
kubectl get nodes -o wide

# 모든 Pod Running
kubectl get pods -A | grep -vE 'Running|Completed'

# 핵심 워크로드 동작 (시나리오 앱)
kubectl get pods -n order
kubectl get ingress -n order
```

## 6. (옵션) 워크로드 부하 테스트로 회귀 검증

```bash
# Module 14 의 burst 시나리오를 다시 한 번
ALB_DNS=$(kubectl get ingress -n order msa -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -sX POST http://$ALB_DNS/api/orders -H 'Content-Type: application/json' -d '{"user_id":"u1","amount":100}' | jq
```

## 7. 다음 분기 업그레이드 준비

업그레이드 했으니 다음 분기 (1.31 → 1.32) 도 동일 흐름. 자동화 권장:
- Terraform 으로 cluster_version 변수만 변경
- CI 에서 plan → 사람 승인 → apply
- Insights 자동 점검을 PR check 로

## 학습 확인

- addon 자동 업그레이드 옵션이 있는가? (`auto_update`)
- Karpenter 의 Drift 가 노드 그룹 업그레이드보다 좋은 점은?
- Blue/Green 클러스터 전환 시 데이터 (PVC) 는 어떻게?

다음: [quiz.md](./quiz.md)
