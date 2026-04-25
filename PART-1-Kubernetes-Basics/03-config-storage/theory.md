# 이론 — Config & Storage

## 1. 12-factor: 설정과 코드 분리

> "설정은 환경에 의해 변하지만, 코드는 변하지 않아야 한다."

K8s가 제공하는 두 도구:
- **ConfigMap** — 평문 설정 (DB 호스트, 기능 플래그, 로그 레벨)
- **Secret** — 민감 정보 (DB 비밀번호, API 키, TLS 인증서)

같은 이미지를 dev/staging/prod에 배포하면서 ConfigMap만 다르게 → 환경별 동작 차이.

## 2. ConfigMap

### 2.1 만들기 (3가지 방법)

**a) literal**
```bash
kubectl create configmap app-config \
  --from-literal=LOG_LEVEL=info \
  --from-literal=DB_HOST=postgres
```

**b) 파일에서**
```bash
kubectl create configmap app-config --from-file=config.yaml
# 또는 디렉토리 전체:
kubectl create configmap nginx-conf --from-file=./conf.d/
```

**c) 매니페스트**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  LOG_LEVEL: info
  DB_HOST: postgres
  # 멀티라인도 가능
  config.yaml: |
    server:
      port: 8080
```

### 2.2 Pod에서 사용 (3가지 방법)

**a) 환경변수**
```yaml
spec:
  containers:
    - name: app
      envFrom:
        - configMapRef:
            name: app-config       # 모든 키를 env로 주입
      env:
        - name: LOG_LEVEL          # 특정 키만
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: LOG_LEVEL
```

**b) 파일 마운트** (멀티라인 설정 파일 등)
```yaml
spec:
  containers:
    - name: app
      volumeMounts:
        - name: config
          mountPath: /etc/app
  volumes:
    - name: config
      configMap:
        name: app-config
```

→ `/etc/app/config.yaml` 등이 자동 생성됨.

**c) command line 인자** (덜 흔함)

### 2.3 ConfigMap 변경 시 동작

- 환경변수로 주입한 경우: **Pod 재시작 전까지 안 바뀜**
- 볼륨 마운트의 경우: 자동 반영 (수십 초 ~ 1분 후 파일 갱신)

→ 앱이 hot-reload를 지원해야 의미 있음.

## 3. Secret

### 3.1 ConfigMap과 거의 같음, 차이점

- 데이터가 **base64로 인코딩**되어 저장 (암호화는 아님!)
- etcd 자체 암호화는 클러스터 설정으로 활성화 가능 (EKS는 기본 암호화)
- RBAC으로 더 엄격하게 보호하는 게 보통

### 3.2 만들기

```bash
kubectl create secret generic db-secret \
  --from-literal=DB_PASSWORD=super-secret \
  --from-literal=API_KEY=abc123
```

매니페스트 (참고만 — git에 커밋 절대 금지):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
data:
  DB_PASSWORD: c3VwZXItc2VjcmV0     # base64
```

### 3.3 외부 Secret Manager 통합

운영에서는 K8s Secret 자체에 민감 데이터를 넣기보다:
- **AWS Secrets Manager** + **Secrets Store CSI Driver** (Part 2~3에서 가능)
- **External Secrets Operator** — Secret을 외부 저장소와 동기화

## 4. Volume — Pod 라이프사이클을 넘어서는 데이터

### 4.1 Volume 타입

- **emptyDir** — Pod 라이프사이클 동안만, 같은 Pod의 컨테이너 간 공유
- **hostPath** — 노드 파일시스템 마운트 (위험, 학습 외 비추천)
- **configMap / secret** — 위에서 본 그것
- **persistentVolumeClaim** — **이게 메인**. PV를 동적으로 받아옴

### 4.2 PV와 PVC의 관계

```
[클러스터 관리자] → PV (PersistentVolume)
                         │ (binding)
[앱 개발자]      → PVC (PersistentVolumeClaim) → Pod에서 사용
```

- **PV**: 실제 스토리지 (EBS, EFS, NFS, ...). cluster-scoped.
- **PVC**: "나 X GB 저장공간 필요해"라는 요청. namespace-scoped.

### 4.3 동적 프로비저닝 (Dynamic Provisioning)

수동으로 PV를 미리 만들 필요 없이, **StorageClass + PVC** 만으로 자동 생성.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
spec:
  storageClassName: gp3       # ← StorageClass 이름
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
```

EKS에서 EBS CSI Driver가 설치되어 있고 `gp3` StorageClass가 있으면, 위 PVC만으로:
1. EBS 볼륨이 자동 생성
2. 그 볼륨에 매핑되는 PV가 생성
3. PVC와 자동 바인딩
4. Pod에 마운트

### 4.4 accessModes

- **ReadWriteOnce (RWO)** — 한 노드에서 읽기/쓰기. EBS의 기본.
- **ReadOnlyMany (ROX)** — 여러 노드에서 읽기만.
- **ReadWriteMany (RWX)** — 여러 노드에서 읽기/쓰기. EFS, FSx 등.

EBS는 RWO만 지원 → Pod가 같은 EBS 볼륨을 여러 노드에서 동시 사용 불가. **다중 Pod가 데이터 공유** 필요하면 EFS 사용.

### 4.5 Reclaim Policy

PVC를 삭제하면 PV는 어떻게 될까?

- **Delete** (기본): PV와 함께 실제 EBS 볼륨도 삭제
- **Retain**: PV는 남고 데이터 보존 (수동 정리 필요)

학습 시 `Delete`가 편리. 운영 데이터는 `Retain` 권장.

## 5. StatefulSet — 상태가 있는 워크로드

### 5.1 Deployment vs StatefulSet

| | Deployment | StatefulSet |
|---|----------|-------------|
| Pod 이름 | 랜덤 (`web-7b8c9d-aaa`) | 순차 (`redis-0`, `redis-1`) |
| Pod 정체성 | 일회용 | 고정 (재기동 후에도 같은 이름) |
| 시작 순서 | 동시 | 순차 (0번이 Ready 되면 1번 시작) |
| 종료 순서 | 동시 | 역순 |
| PVC | 공유 또는 없음 | Pod별 고유 PVC |
| Service | 보통 ClusterIP | Headless Service 권장 |

### 5.2 언제 쓰나

- **Database**: 각 Pod가 자기 데이터 디스크를 가져야 함
- **Kafka, ZooKeeper**: 클러스터 멤버가 안정된 ID 필요
- **Redis Cluster**: 마스터/레플리카 식별 필요

### 5.3 안정된 네트워크 ID

Headless Service + StatefulSet 조합:
- `redis-0.redis-hl.default.svc.cluster.local`
- `redis-1.redis-hl.default.svc.cluster.local`

→ Pod 재기동 후에도 같은 DNS 이름 유지 → 클러스터 내 다른 Pod가 일관되게 호출 가능.

### 5.4 volumeClaimTemplates

```yaml
spec:
  serviceName: redis-hl
  replicas: 3
  template: ...
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        storageClassName: gp3
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 5Gi
```

→ Pod별로 PVC 자동 생성: `data-redis-0`, `data-redis-1`, `data-redis-2`. 각각 독립된 EBS 볼륨.

다음: [lab-01-configmap-secret.md](./lab-01-configmap-secret.md)
