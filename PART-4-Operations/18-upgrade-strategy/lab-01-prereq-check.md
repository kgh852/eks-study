# Lab 01 — 업그레이드 사전 점검

## 1. 현재 버전 확인

```bash
aws eks describe-cluster --name eks-study --query 'cluster.{version:version,platformVersion:platformVersion,status:status}'

kubectl version --short
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}={.status.nodeInfo.kubeletVersion}{"\n"}{end}'
```

## 2. EKS Upgrade Insights (콘솔 또는 CLI)

```bash
aws eks list-insights --cluster-name eks-study \
  --query 'insights[].[id,name,recommendation,insightStatus.status]' --output table
```

기대 (예시):
```
deprecated-api      Replaceable resource versions detected   PASSING
ekssupport          EKS support status                       UNHEALTHY     ← 필요 시
nodeMaxConfigured   Node Pod density                         PASSING
```

`UNHEALTHY` 가 있으면 그 권고 사항 따르기.

## 3. Deprecated API 사용 여부 (`pluto`)

```bash
brew install FairwindsOps/tap/pluto

# Helm 릴리즈 점검
pluto detect-helm -A

# YAML 파일 점검 (예: 본 커리큘럼 매니페스트)
cd /Users/finn/test/eks-study
pluto detect-files -d ./PART-1-Kubernetes-Basics --target-versions=k8s=v1.31.0

# 클러스터 안의 리소스 점검 (kubectl convert + pluto)
pluto detect-all-in-cluster --target-versions=k8s=v1.31.0
```

기대: deprecated 사용처가 있으면 파일/객체별 출력. 다 통과면 `No problems found`.

## 4. addon 호환 버전 확인

```bash
TARGET=1.31

for addon in vpc-cni coredns kube-proxy aws-ebs-csi-driver; do
  echo "=== $addon ==="
  eksctl utils describe-addon-versions --kubernetes-version $TARGET --name $addon \
    --query 'Addons[0].AddonVersions[0].[AddonVersion,Compatibilities[0].DefaultVersion]' \
    --output text
done
```

## 5. 노드 그룹 AMI 버전

```bash
aws eks describe-nodegroup --cluster-name eks-study --nodegroup-name workers \
  --query 'nodegroup.{releaseVersion:releaseVersion,amiType:amiType,version:version}'
```

## 6. PDB / 워크로드 ready 상태

```bash
kubectl get pdb -A
kubectl get pods -A | grep -vE 'Running|Completed' | head
```

PDB 가 너무 빡빡하면 (`minAvailable: 100%`) 노드 업그레이드 stuck.

## 7. Backup / Disaster Recovery

업그레이드 전 다음을 백업:
```bash
# 클러스터의 모든 매니페스트 export (velero 권장, 학습용은 간단 버전)
mkdir -p /tmp/eks-backup
for ns in default order monitoring kube-system karpenter keda; do
  kubectl get all,cm,secret,pvc,sa,role,rolebinding -n $ns -o yaml > /tmp/eks-backup/${ns}.yaml 2>/dev/null
done
ls -la /tmp/eks-backup/
```

(Secret 은 sensitive 주의 — git 커밋 금지)

## 8. 학습 확인

- skew policy (kubelet vs apiserver) 이 허용하는 차이는?
- `kubectl convert` 의 용도는?
- velero 가 K8s backup 에 적합한 이유는?

다음: [lab-02-control-plane.md](./lab-02-control-plane.md)
