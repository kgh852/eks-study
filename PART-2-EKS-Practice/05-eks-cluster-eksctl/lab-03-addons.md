# Lab 03 — Addon 관리

## 학습 확인 포인트

- [ ] EKS addon vs 자체 설치(Helm)의 차이를 안다
- [ ] addon 버전 업그레이드 흐름을 봤다

## 1. 현재 설치된 addon 확인

```bash
eksctl get addon --cluster eks-study --region ap-northeast-2
```

기대:
```
NAME                  VERSION                STATUS  IAMROLE
aws-ebs-csi-driver    v1.32.0-eksbuild.1     ACTIVE  arn:aws:iam::xxx:role/...
coredns               v1.11.1-eksbuild.6     ACTIVE
kube-proxy            v1.30.0-eksbuild.3     ACTIVE
vpc-cni               v1.18.x-eksbuild.x     ACTIVE  arn:aws:iam::xxx:role/...
```

## 2. AWS managed addon vs Helm 설치 차이

| | EKS addon | Helm 직접 설치 |
|---|---|---|
| 설치 방법 | `eksctl create addon` 또는 콘솔 | `helm install` |
| 업그레이드 | EKS 가이드 / `eksctl update addon` | `helm upgrade` |
| EKS 버전과 호환성 | AWS 보장 | 직접 확인 |
| 커스터마이징 | 제한 (configurationValues) | 완전 |
| 비용 | 무료 (워크로드만 청구) | 무료 |

**기본 정책**:
- vpc-cni, coredns, kube-proxy, ebs-csi → addon 권장
- AWS Load Balancer Controller, Karpenter, KEDA → Helm 권장 (커스터마이징 많음)

## 3. addon 사용 가능한 버전 보기

```bash
eksctl utils describe-addon-versions \
  --kubernetes-version 1.30 --name vpc-cni \
  --query 'Addons[].AddonVersions[].AddonVersion' --output text \
  | head -5
```

## 4. addon 업그레이드 흐름 (시뮬레이션)

```bash
# 현재 버전 확인
CURRENT=$(eksctl get addon --cluster eks-study --name vpc-cni \
  -o json | jq -r '.[0].Version')
echo "Current vpc-cni version: $CURRENT"

# 업그레이드 (실제로는 한 단계 위 버전이 있을 때만 의미)
# eksctl update addon --name vpc-cni --version <newer> --cluster eks-study --force
```

## 5. addon 자체 설정 변경 (configurationValues)

vpc-cni 의 환경변수 변경 예시:
```bash
eksctl update addon \
  --name vpc-cni \
  --cluster eks-study \
  --region ap-northeast-2 \
  --configuration-values '{"env":{"WARM_IP_TARGET":"5"}}'

# DaemonSet의 env 확인
kubectl describe ds aws-node -n kube-system | grep -A2 'WARM_IP_TARGET'
```

## 6. addon 삭제 (학습 후)

이 lab의 변경(`WARM_IP_TARGET`)을 되돌리려면 다시 `--configuration-values '{}'` 로 update.
addon 자체를 삭제하면 vpc-cni 가 빠져 노드 통신이 끊깁니다 — **하지 마세요**.

## 학습 확인 질문

1. `vpc-cni` addon 을 삭제하면 어떻게 되는가?
2. `aws-ebs-csi-driver` addon이 IRSA를 자동 셋업해 주는 이유는?
3. CoreDNS addon 의 ConfigMap을 수동 편집했는데 EKS addon이 덮어쓰는 동작을 본 적 있다면? 어떻게 막을까?

다음: [quiz.md](./quiz.md)
