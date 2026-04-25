resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.0.6"

  values = [
    yamlencode({
      settings = {
        clusterName       = module.eks.cluster_name
        interruptionQueue = module.karpenter.queue_name
      }
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = module.karpenter.iam_role_arn
        }
      }
      controller = {
        resources = {
          requests = { cpu = "100m", memory = "512Mi" }
          limits   = { memory = "1Gi" }
        }
      }
    })
  ]

  depends_on = [module.eks, module.karpenter]
}

# 기본 NodePool + EC2NodeClass (Karpenter 가 떠있어야 적용 가능 → time_sleep)
resource "time_sleep" "wait_karpenter" {
  depends_on      = [helm_release.karpenter]
  create_duration = "30s"
}

resource "kubernetes_manifest" "default_nodepool" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "default" }
    spec = {
      template = {
        metadata = {
          labels = { managed-by = "karpenter" }
        }
        spec = {
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot"] },
            { key = "karpenter.k8s.aws/instance-cpu", operator = "In", values = ["2", "4", "8"] },
            { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["2"] }
          ]
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          expireAfter = "168h"
        }
      }
      limits = { cpu = "100" }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "30s"
      }
    }
  }
  depends_on = [time_sleep.wait_karpenter]
}

resource "kubernetes_manifest" "default_ec2nodeclass" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      amiFamily = "AL2023"
      amiSelectorTerms = [
        { alias = "al2023@latest" }
      ]
      role = module.karpenter.node_iam_role_name
      subnetSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
      ]
      securityGroupSelectorTerms = [
        { tags = { "karpenter.sh/discovery" = var.cluster_name } }
      ]
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize = "30Gi"
            volumeType = "gp3"
            encrypted  = true
          }
        }
      ]
      tags = var.tags
    }
  }
  depends_on = [time_sleep.wait_karpenter]
}
