# 이론 — Terraform IaC for EKS

## 1. eksctl vs Terraform

| 항목 | eksctl | Terraform |
|------|--------|-----------|
| 학습 곡선 | 낮음 | 중 |
| 단일 명령으로 클러스터 | ✓ | ✓ |
| State 관리 | CFN Stack | tfstate (S3 + DynamoDB lock 권장) |
| 다중 환경 | ClusterConfig 파일 별 | workspace + tfvars |
| K8s 리소스 적용 | 별도 (helm/kubectl) | provider 로 통합 가능 |
| 협업 | 각자 만들기 | tfstate 공유로 협업 |
| 운영 표준 | 학습/PoC | 실무 |

**실무 권장**: Terraform. 하지만 Karpenter / KEDA 같은 일부 컴포넌트는 Helm 으로 + Terraform 의 `helm_release` 리소스로 묶기.

## 2. 모듈 구조

```
terraform/
├── versions.tf           # provider 버전
├── variables.tf          # 입력 변수 (cluster_name, region, ...)
├── locals.tf             # 계산된 값
├── outputs.tf            # 다른 stack 이 쓸 출력
│
├── vpc.tf                # VPC + 서브넷 (terraform-aws-modules/vpc/aws)
├── eks.tf                # EKS Cluster (terraform-aws-modules/eks/aws)
├── irsa.tf               # IRSA 모듈들 (LB Controller, EBS, Karpenter)
├── karpenter.tf          # Karpenter Helm
├── keda.tf               # KEDA Helm
└── alb-controller.tf     # AWS LB Controller Helm
```

## 3. 핵심 모듈

### 3.1 terraform-aws-modules/vpc/aws

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "eks-study-tf"
  cidr = "10.30.0.0/16"

  azs              = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c"]
  private_subnets  = ["10.30.1.0/24", "10.30.2.0/24", "10.30.3.0/24"]
  public_subnets   = ["10.30.101.0/24", "10.30.102.0/24", "10.30.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true   # 학습용 (운영은 false)
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = "eks-study-tf"
  }
}
```

### 3.2 terraform-aws-modules/eks/aws

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "eks-study-tf"
  cluster_version = "1.30"

  cluster_endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    vpc-cni                = { most_recent = true }
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    aws-ebs-csi-driver     = { most_recent = true }
  }

  eks_managed_node_groups = {
    workers = {
      min_size     = 0
      max_size     = 6
      desired_size = 2

      instance_types = ["t3.medium", "t3a.medium"]
      capacity_type  = "SPOT"

      labels = {
        workload-type = "general"
      }
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = "eks-study-tf"
  }
}
```

### 3.3 IRSA (LB Controller 예시)

```hcl
module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${module.eks.cluster_name}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}
```

### 3.4 Helm 으로 Karpenter

```hcl
resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.0.6"

  set {
    name  = "settings.clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter_irsa.iam_role_arn
  }

  depends_on = [module.eks]
}
```

## 4. State 관리

학습용 — 로컬 state OK.
운영 — S3 backend + DynamoDB lock:
```hcl
terraform {
  backend "s3" {
    bucket         = "my-tf-state"
    key            = "eks/eks-study/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "tf-state-lock"
    encrypt        = true
  }
}
```

## 5. 환경 분리 패턴

방법 1 — **workspace**:
```bash
terraform workspace new dev
terraform workspace select dev
terraform apply
```

방법 2 — **디렉토리**:
```
terraform/
├── modules/eks/         # 공통 모듈
├── envs/dev/main.tf     # dev 환경
└── envs/prod/main.tf
```

운영은 디렉토리 분리 권장 (state 분리 + IAM 분리 가능).

다음: [lab-01-cluster.md](./lab-01-cluster.md)
