# 이론 — Pod, ReplicaSet, Deployment, Namespace

## 1. Pod — Kubernetes의 최소 배포 단위

### 1.1 컨테이너와 Pod의 차이

Docker만 쓸 때는 "컨테이너 하나를 띄운다" 가 단위였습니다. K8s는 **Pod** 라는 한 단계 위 추상화를 단위로 씁니다.

```
+-------------------- Pod ----------------------+
|                                                |
|   +-------------+    +-------------------+    |
|   | container A |    | container B (sidecar) | |
|   +-------------+    +-------------------+    |
|                                                |
|   Shared:  ┌─ network namespace (같은 IP)      |
|            ├─ IPC namespace                    |
|            └─ Volumes                          |
+------------------------------------------------+
```

**Pod 안의 컨테이너들은:**
- 같은 IP를 공유 (서로 `localhost`로 호출 가능)
- 같은 볼륨을 마운트 가능
- 함께 스케줄링됨 (같은 노드에 배치)
- 함께 시작/종료됨

### 1.2 왜 Pod라는 추상화가 필요한가?

**시나리오**: 메인 앱 + 사이드카 (로그 수집기, 프록시 등)
- 메인 앱이 파일에 로그를 씀
- 사이드카가 그 파일을 읽어 외부로 전송
- 같은 호스트에 있어야 효율적, 같이 죽고 같이 살아야 일관성 유지

→ Pod라는 단위가 이런 상호 의존 컨테이너들을 묶기에 자연스럽다.

### 1.3 Pod 라이프사이클

```
Pending  →  Running  →  Succeeded
                    ↘  Failed
                    ↘  Unknown
```

- **Pending**: 노드에 스케줄링 대기, 또는 이미지 pull 중
- **Running**: 최소 1개 컨테이너가 실행 중
- **Succeeded**: 모든 컨테이너가 성공적으로 종료
- **Failed**: 어떤 컨테이너가 실패로 종료
- **Unknown**: 노드와 통신 불가

### 1.4 Pod는 단명(ephemeral)하다

Pod는 직접 만들 수 있지만, **거의 안 씁니다.** 노드 장애나 업데이트가 일어나면 그냥 사라집니다. 그래서 Pod의 복제본을 보장해주는 상위 컨트롤러가 필요합니다 → **ReplicaSet/Deployment**.

---

## 2. ReplicaSet — 복제본 수 보장

ReplicaSet은 "Pod 3개 항상 떠 있어야 함"같은 **목표 상태**를 유지합니다.

```
ReplicaSet (replicas: 3)
   ├── Pod-abc (생성됨)
   ├── Pod-def (생성됨)
   └── Pod-ghi (생성됨)

[누가 Pod-def 죽임] → ReplicaSet이 새로 생성
   ├── Pod-abc
   ├── Pod-jkl  ← 새로 만든 거
   └── Pod-ghi
```

### 동작 원리

1. ReplicaSet은 `selector`로 자기가 관리할 Pod를 식별
2. 현재 Pod 수를 세어 `replicas` 와 비교
3. 부족하면 만들고, 많으면 삭제

### 실무에서 직접 쓰지는 않는다

ReplicaSet 위에 **Deployment** 가 있으니 직접 쓸 일은 거의 없습니다. 하지만 동작은 알아야 합니다 — Deployment가 만든 ReplicaSet이 고장 났을 때 디버깅하려면.

---

## 3. Deployment — 실무 표준

Deployment는 ReplicaSet에 다음 기능을 더한 것:

- **롤링 업데이트** (점진적 교체)
- **롤백** (이전 버전으로 되돌리기)
- **버전 이력** 관리

### 3.1 롤링 업데이트 시나리오

```
초기 상태:  ReplicaSet-v1 [Pod, Pod, Pod]
            ┌──── 사용자 트래픽 ────┐

이미지 업데이트 (kubectl set image):
            ReplicaSet-v1 [Pod, Pod, Pod]   ← 줄어듦
            ReplicaSet-v2 [Pod]              ← 늘어남

진행:       ReplicaSet-v1 [Pod]
            ReplicaSet-v2 [Pod, Pod]

완료:       ReplicaSet-v1 []                 ← 0으로
            ReplicaSet-v2 [Pod, Pod, Pod]
```

이 과정 동안 사용자 트래픽은 끊기지 않습니다 (양쪽 ReplicaSet의 Pod가 동시에 살아있는 시점이 있음).

### 3.2 strategy 옵션

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 25%        # 평소 replicas의 25%까지 더 만들 수 있음
    maxUnavailable: 25%  # 평소 replicas의 25%까지 못 쓸 수 있음
```

`replicas: 4` 일 때 `maxSurge=25%, maxUnavailable=25%` →
- 동시에 살아있는 Pod 최대 5개 (4 + 1)
- 동시에 사용 가능한 Pod 최소 3개 (4 - 1)

### 3.3 롤백

```bash
kubectl rollout history deployment/my-app
kubectl rollout undo deployment/my-app                # 직전 리비전으로
kubectl rollout undo deployment/my-app --to-revision=2
```

내부적으로는 이전 ReplicaSet의 replicas를 늘리고 현재 ReplicaSet의 replicas를 줄이는 식으로 동작.

---

## 4. Namespace — 논리적 격리

### 4.1 개념

K8s 클러스터 안에서 리소스를 그룹화하는 가상 공간:

```
Cluster
├── Namespace: default        ← 명시 안하면 여기로
├── Namespace: kube-system    ← K8s 시스템 컴포넌트
├── Namespace: prod-app       ← 운영 앱
└── Namespace: dev-app        ← 개발 앱
```

### 4.2 격리되는 것 / 안 되는 것

**격리되는 것**:
- Pod, Deployment, Service, ConfigMap, Secret 등 대부분 객체
- 같은 이름을 다른 NS에 쓸 수 있음 (`prod-app/my-svc` ≠ `dev-app/my-svc`)
- RBAC, ResourceQuota, LimitRange가 NS 단위로 적용 가능

**격리 안 되는 것 (cluster-scoped)**:
- Node, PersistentVolume, StorageClass, ClusterRole, Namespace 자체

### 4.3 DNS

같은 NS의 Service는 짧은 이름으로:
```
http://my-svc/
```

다른 NS의 Service는 FQDN으로:
```
http://my-svc.other-namespace.svc.cluster.local/
```

### 4.4 사용 패턴

| 기준 | 분리 정책 |
|------|----------|
| 환경 | `prod` / `staging` / `dev` |
| 팀 | `team-a` / `team-b` |
| 시스템 | `kube-system` / `monitoring` / `karpenter` |
| 멀티테넌트 | 고객별 NS |

---

## 5. 객체 간 관계 정리

```
Deployment
    └── (관리) ReplicaSet (현재/구 버전 모두 관리 가능)
                    └── (생성) Pod
                                └── (포함) Container(s)

         ↑ 모두 Namespace 안에 존재
```

**관리 흐름**:
- `Deployment` 의 `replicas`/이미지 변경 → ReplicaSet 갱신/생성
- ReplicaSet은 항상 `replicas` 수만큼 Pod 유지
- Pod는 컨테이너를 실제로 노드에 띄움

다음: [lab-01-pod.md](./lab-01-pod.md)
