# Part 1 미니 프로젝트 — order-service 단독 배포

## 목표

지금까지 배운 모든 개념을 통합:

- Helm 차트로 패키징된 `order-service` 를 **최소 EKS 클러스터에 배포**
- `Service` 로 내부 노출 + `port-forward` 로 외부 접근 (LB 비용 절감)
- ConfigMap으로 환경변수 주입
- ServiceAccount + RoleBinding (자기 자신의 정보만 조회 가능)
- HPA 활성화 후 부하 발생 → Pod 늘어나는 것 확인

## 산출물

- 배포된 order-service Pod 2~10개
- HPA 동작으로 Pod 수가 부하에 반응
- `kubectl logs` 로 요청 로그 확인 가능
- 정리 후 잔존 리소스 0

---

## 1. 사전 준비 점검

```bash
# 클러스터
kubectl get nodes
kubectl get csidrivers ebs.csi.aws.com

# metrics-server (HPA에 필수)
kubectl get deploy -n kube-system metrics-server
```

`metrics-server` 가 없으면 설치:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl wait --for=condition=available --timeout=60s deploy/metrics-server -n kube-system
```

EKS의 일부 환경에서는 metrics-server의 `--kubelet-insecure-tls` 플래그가 필요할 수 있음:
```bash
kubectl patch deploy metrics-server -n kube-system --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}
]'
```

## 2. 이미지 빌드 + ECR 푸시

```bash
cd /Users/finn/test/eks-study
bash 00-prerequisites/scripts/ecr-push-all.sh
```

확인:
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2
aws ecr describe-images \
  --repository-name eks-study/order-service \
  --query 'imageDetails[].imageTags[]' --output text
```

## 3. values 파일 만들기

```bash
cd PART-1-Kubernetes-Basics/04-rbac-helm
cat > values-prod.yaml <<EOF
replicaCount: 2

image:
  repository: ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/eks-study/order-service
  tag: latest

env:
  PORT: "8080"
  LOG_LEVEL: info

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 8
  targetCPUUtilizationPercentage: 50
EOF
```

## 4. Helm 설치

```bash
helm install order-service ./charts/order-service \
  -f values-prod.yaml \
  --namespace order --create-namespace

helm list -n order
kubectl get all -n order
```

## 5. 동작 검증

### 헬스체크
```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=order-service -n order --timeout=120s
kubectl port-forward svc/order-service -n order 8080:80 &
PF_PID=$!

curl -s http://localhost:8080/healthz -w "\n%{http_code}\n"
```

기대: `200`.

### POST /orders + GET /orders/:id
```bash
RESP=$(curl -s -X POST http://localhost:8080/orders \
  -H 'Content-Type: application/json' \
  -d '{"user_id":"u1","amount":1000}')
echo "$RESP"

ID=$(echo $RESP | jq -r '.id')
curl -s http://localhost:8080/orders/$ID
```

기대: 생성된 ID로 GET 시 동일한 주문 정보 반환.

## 6. 부하 발생 + HPA 동작 관찰

별도 터미널 1: HPA 와 Pod 수 watch
```bash
watch -n2 'kubectl get hpa,pods -n order'
```

별도 터미널 2: 부하 발생기
```bash
kubectl run -it --rm load \
  --image=alpine \
  -n order \
  --restart=Never \
  -- sh -c 'apk add -q curl && while true; do
    curl -s -X POST http://order-service/orders \
      -H "Content-Type: application/json" \
      -d "{\"user_id\":\"u1\",\"amount\":100}" > /dev/null
  done'
```

watch 화면에서 본 흐름:
```
HPA  TARGETS    MINPODS  MAXPODS  REPLICAS
...   45%/50%   2        8        2

→ 시간이 흐르며:
...   80%/50%   2        8        2     ← target 초과
...   80%/50%   2        8        4     ← Pod 증가
...   60%/50%   2        8        6
```

5~10분 정도 반응 시간 (HPA는 1분 단위 평가).

## 7. 부하 종료 후 축소 관찰

부하 컨테이너 Ctrl+C 종료 → 5~10분 후:
```
...   30%/50%   2        8        4
...   15%/50%   2        8        2     ← min 으로 축소
```

scale down은 scale up 보다 보수적 (기본 5분 stabilization window).

## 8. 정리 (반드시!)

```bash
kill $PF_PID 2>/dev/null
helm uninstall order-service -n order
kubectl delete ns order
rm -f values-prod.yaml
```

## 9. 회고 질문

- Pod이 늘어나는 데 시간이 왜 그렇게 걸렸나? (스케줄링, 이미지 pull, readinessProbe)
- HPA 의 `targetCPUUtilizationPercentage: 50` 을 70으로 올리면 어떻게 동작이 변할까?
- Helm 차트의 어느 부분을 수정하면 ConfigMap 도 같이 배포되도록 할 수 있을까?

## Part 1 종료

축하합니다 🎉 — Part 1을 마쳤습니다.

다음 Part 2는 EKS 운영 본격: VPC CNI, ALB Controller, IRSA, 관측 스택 설치.

```bash
# Part 1 학습이 모두 끝났다면 클러스터를 삭제해 비용을 멈추세요:
eksctl delete cluster --name eks-study --region ap-northeast-2
```
