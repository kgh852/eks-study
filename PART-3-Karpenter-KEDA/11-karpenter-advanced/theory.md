# 이론 — Karpenter Advanced

## 1. Spot 안정성의 본질

Spot 인스턴스는 AWS 가 capacity 부족 시 회수합니다 (2분 통지). 안정성은 **다양화** 로 달성:

- **인스턴스 타입 다양화**: 같은 시점에 모든 family 가 회수될 가능성은 낮음
- **AZ 다양화**: 한 AZ 의 capacity 부족이 다른 AZ 에 영향 적음
- **세대 다양화**: c5 + c6 + c7 등 여러 세대 혼합

NodePool 의 `requirements` 가 다양할수록 Karpenter 의 **Price-Capacity-Optimized** 알고리즘이 안정적인 선택을 함.

```yaml
requirements:
  - key: karpenter.k8s.aws/instance-family
    operator: In
    values: [c5, c5a, c5d, c6a, c6i, c6id, m5, m5a, m5d, m6a, m6i, m6id]
  - key: karpenter.k8s.aws/instance-cpu
    operator: In
    values: ["2", "4", "8"]
  - key: topology.kubernetes.io/zone
    operator: In
    values: [ap-northeast-2a, ap-northeast-2b, ap-northeast-2c]
```

## 2. On-Demand Fallback 패턴

Spot 이 부족할 때 자동으로 On-Demand 로 전환하는 패턴 — 두 NodePool 사용:

```yaml
# NodePool: spot
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: [spot]
  weight: 100      # 우선순위 높음

---
# NodePool: ondemand
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: [on-demand]
  weight: 10       # 낮음 — Spot 시도 후 안 되면 여기로
```

→ Karpenter 는 weight 높은 것 먼저, 못 만들면 다음.

## 3. Disruption 의 4가지 트리거

### 3.1 Empty (또는 Underutilized)
이미 lab-03 에서 다룸. `consolidationPolicy` 로 제어.

### 3.2 Drift
EC2NodeClass 또는 NodePool 의 spec 이 변하면 기존 노드가 "drift" 상태가 됨. 새 spec 으로 노드를 만들고 기존 노드를 제거 — **무중단 spec 변경**.

```bash
kubectl get nodeclaims -L karpenter.sh/drifted
```

### 3.3 Expiration
```yaml
disruption:
  expireAfter: 168h    # 7일 후 노드 강제 회전
```

→ 보안 패치 자동 반영. AMI 업데이트 시 Drift 와 함께 작동.

### 3.4 Spot Interruption
이미 lab-01 의 SQS 큐가 받음. Karpenter 가 자동으로 cordon → drain → 다른 노드 미리 만듦.

## 4. Disruption Budget

너무 많은 노드를 한번에 회수하면 워크로드 영향. Budget 으로 제한:

```yaml
disruption:
  budgets:
    - nodes: "20%"        # 동시에 20% 까지만 disruption 허용
    - nodes: "0"          # 특정 시간대 차단
      schedule: "0 9 * * mon-fri"     # 평일 09:00 시작
      duration: 8h                     # 8시간 동안 (업무 시간)
```

→ 평일 업무 시간엔 disruption 없음, 그 외엔 20% 제한.

## 5. Block Device 와 인스턴스 스토어

EC2NodeClass:
```yaml
blockDeviceMappings:
  - deviceName: /dev/xvda           # 루트 볼륨
    ebs:
      volumeSize: 50Gi
      volumeType: gp3
      iops: 3000
      throughput: 125
      encrypted: true

instanceStorePolicy: RAID0           # 인스턴스 스토어를 RAID0 으로 (NVMe 다중 디스크 인스턴스 타입)
```

Spot 우대 받으면서 일시 캐시/스왑이 필요한 워크로드면 인스턴스 스토어 활용.

## 6. NodePool 분리 패턴 (실무)

**시나리오 1 — workload-tier 별**:
- `tier-base`: 항상 켜둘 컴포넌트 (모니터링, ingress) → On-Demand
- `tier-burst`: 가변 워크로드 → Spot

**시나리오 2 — 인스턴스 종류 별**:
- `cpu`: 컴퓨팅 집약
- `memory`: 메모리 집약 (DB, 캐시)
- `gpu`: ML 워크로드 (taint 적용)

**시나리오 3 — 환경 별**:
- `prod-spot`, `prod-ondemand`
- `staging-spot`

NodePool 의 라벨 + Pod 의 nodeSelector 로 강제.

## 7. Karpenter v1 의 변화점 (2024)

- `Provisioner` (옛 v1alpha) → `NodePool` (v1)
- `AWSNodeTemplate` → `EC2NodeClass`
- 다중 disruption 정책 + Budget 도입
- Drift 가 기본 활성

기존 자료가 옛 CRD 이름을 쓰면 주의.

다음: [lab-01-spot-diversity.md](./lab-01-spot-diversity.md)
