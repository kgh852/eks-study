# 이론 — MSA 배포 아키텍처

## 1. 배포할 서비스

| 서비스 | 타입 | 외부 노출 | 내부 통신 | 외부 의존 |
|--------|------|-----------|-----------|----------|
| frontend | Deployment + Ingress | ALB (HTTP) | order, user 호출 | - |
| order-service | Deployment + Ingress | ALB (HTTP) `/api/orders` | user-service gRPC 호출 | - |
| user-service | Deployment + ClusterIP | - (내부만) | - | - |
| payment-service | Deployment | - | - | AWS SQS |
| notification-service | Deployment | - | - | Kafka (외부 또는 in-cluster) |

**디자인 결정**:
- DB 없음 — 학습 단순화 (in-memory)
- StatefulSet 안 씀 — Pod 정체성 불필요
- 외부 큐 (SQS, Kafka) 는 Part 3 에서 본격 사용

## 2. 토폴로지

```
         (Internet)
            │
            ▼
     ┌─── ALB (group: eks-study) ───┐
     │                               │
     │  /            → frontend      │
     │  /api/orders  → order-service │
     │  /api/users   → user-service  │ (REST 게이트웨이는 없으므로 user는 노출 안 함)
     └───────────────────────────────┘
                 │
                 ▼
        ┌─ K8s ClusterIP ─┐
        │                  │
        │  order-service ─→ user-service (gRPC :50051)
        │       │
        │  payment-service ─→ (Container Insights / Prometheus 메트릭)
        │       │
        │  notification-service
        └──────────────────┘
                 │
                 ▼
        AWS SQS, External Kafka
```

## 3. 공유 패턴

### 3.1 같은 NS

`order` namespace 에 5개 서비스 모두 배포 → DNS 짧은 이름 사용.

### 3.2 ECR Pull Secret 불필요

노드 IAM Role 에 `AmazonEC2ContainerRegistryReadOnly` 정책이 있으므로 Pod 가 ECR 에서 직접 pull. (Self-managed 노드 그룹에서도 노드 IAM Role 에 추가만 해주면 됨.)

### 3.3 Health check 통일

모든 서비스가 `/healthz` (메인 포트) 또는 `:9090/healthz` (메트릭 포트) 노출.

## 4. ALB 그룹화

여러 Ingress 가 ALB 를 공유:
```yaml
annotations:
  alb.ingress.kubernetes.io/group.name: eks-study   # 같은 그룹은 같은 ALB
  alb.ingress.kubernetes.io/group.order: "10"        # 우선순위
```

→ ALB 1개 비용으로 다중 호스트/경로 라우팅. 본 lab은 단일 그룹 사용.

## 5. ServiceMonitor 일괄 등록

각 서비스마다 ServiceMonitor 만들 수도 있고, 공용 ServiceMonitor로 한 번에 처리도 가능.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: order-services
  namespace: monitoring
  labels:
    release: kps
spec:
  namespaceSelector:
    matchNames: ["order"]
  selector:
    matchLabels:
      eks-study/scrape: "true"
  endpoints:
    - port: metrics
      path: /metrics
      interval: 15s
```

→ Service 에 `eks-study/scrape: "true"` 라벨만 붙이면 자동 scrape.

## 6. Resource Sizing

학습용 가벼운 설정:

| 서비스 | requests | limits |
|--------|----------|--------|
| frontend | 50m / 64Mi | 200m / 128Mi |
| order-service | 100m / 128Mi | 500m / 256Mi |
| user-service | 100m / 128Mi | 500m / 256Mi |
| payment-service | 50m / 64Mi | 200m / 128Mi |
| notification-service | 50m / 64Mi | 200m / 128Mi |

총 requests: ~350m CPU + ~448Mi Memory → t3.medium 노드 1대로도 충분.

다음: [lab-01-prepare.md](./lab-01-prepare.md)
