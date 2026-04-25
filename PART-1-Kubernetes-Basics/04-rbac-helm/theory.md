# 이론 — RBAC & Helm

## 1. RBAC 핵심 4객체

```
ServiceAccount  ──[bound by]──→  RoleBinding  ──[ref]──→  Role
   (누가)                                                    (무엇을 할 수 있는가)

ServiceAccount  ──[bound by]──→  ClusterRoleBinding  ──→  ClusterRole
   (cluster-scope)                                          (cluster-scope)
```

### 1.1 ServiceAccount (SA) — "누구"

- Pod에 자동 첨부 (`spec.serviceAccountName` 미지정 시 `default` SA 사용)
- 자체 토큰을 가지고 K8s API 호출 시 인증
- IRSA(Part 2)에서는 AWS IAM Role과 매핑

### 1.2 Role / ClusterRole — "무엇을"

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: default
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
```

- **Role**: 단일 NS 안에서 권한
- **ClusterRole**: 클러스터 전체 (또는 cluster-scoped 리소스: Node, PV, ClusterRole 자체 등)

verbs 종류:
- `get`, `list`, `watch` (읽기)
- `create`, `update`, `patch`, `delete` (쓰기)
- `*` (전부)

### 1.3 RoleBinding / ClusterRoleBinding — "결합"

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: default
subjects:
  - kind: ServiceAccount
    name: my-sa
    namespace: default
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

이걸 적용하면: `default` NS의 `my-sa` 가 `pod-reader` Role을 갖게 됨.

### 1.4 매트릭스로 정리

|  | namespace 한정 | cluster-wide |
|---|---|---|
| 권한 정의 | `Role` | `ClusterRole` |
| 권한 결합 | `RoleBinding` | `ClusterRoleBinding` |

조합 규칙:
- `RoleBinding` + `Role` → 한 NS 안의 권한
- `RoleBinding` + `ClusterRole` → ClusterRole의 정의를 한 NS에서만 사용 (재사용 패턴)
- `ClusterRoleBinding` + `ClusterRole` → 클러스터 전역
- `ClusterRoleBinding` + `Role` → ❌ 불가능

### 1.5 권한 점검 명령

```bash
kubectl auth can-i list pods --as=system:serviceaccount:default:my-sa
kubectl auth can-i create deployments --as=system:serviceaccount:prod:deployer -n prod
```

`yes` / `no` 로 답해줍니다.

## 2. Helm — K8s 패키지 매니저

### 2.1 왜 필요한가

매니페스트 직접 관리의 한계:
- 환경별 변수 (이미지 태그, replicas) 수동 치환 → 휴먼 에러
- 매니페스트 10개 묶음을 한 번에 install/upgrade 불편
- 의존성 (예: 앱 + Redis subchart) 관리 불편

Helm이 해결:
- 차트 (Chart) = 매니페스트 템플릿 + 기본 values
- `values.yaml` 로 환경 분리
- `helm install/upgrade/rollback/uninstall` 한 단어

### 2.2 차트 구조

```
mychart/
├── Chart.yaml             # 차트 메타 (이름, 버전)
├── values.yaml            # 기본 values
├── templates/
│   ├── _helpers.tpl       # 공용 함수 (예: full name 만들기)
│   ├── deployment.yaml    # Go template
│   ├── service.yaml
│   ├── ingress.yaml
│   └── configmap.yaml
├── charts/                # 의존 차트 (subchart)
└── README.md
```

### 2.3 템플릿 문법 미리보기

`templates/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "mychart.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "mychart.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: {{ .Values.service.port }}
```

`values.yaml`:
```yaml
replicaCount: 3
image:
  repository: my-app
  tag: v1.0.0
service:
  port: 8080
```

### 2.4 install / upgrade / rollback

```bash
# 설치
helm install my-app ./mychart -n my-ns --create-namespace

# values 오버라이드
helm install my-app ./mychart -f values-prod.yaml --set image.tag=v2

# 업그레이드 (없으면 install)
helm upgrade --install my-app ./mychart -f values-prod.yaml

# 이전 버전으로 롤백
helm history my-app
helm rollback my-app 1

# 삭제
helm uninstall my-app
```

### 2.5 dry-run / template

```bash
# 매니페스트만 렌더링 (배포 안 함)
helm template my-app ./mychart > rendered.yaml

# 서버 측 dry-run (검증)
helm install my-app ./mychart --dry-run --debug
```

### 2.6 차트 검색 / 외부 차트 사용

```bash
helm search hub redis              # ArtifactHub 검색
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install my-redis bitnami/redis --version 18.x.x
```

다음: [lab-01-rbac.md](./lab-01-rbac.md)
