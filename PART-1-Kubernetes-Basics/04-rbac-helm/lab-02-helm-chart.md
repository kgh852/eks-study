# Lab 02 — Helm 차트 작성

## 학습 확인 포인트

- [ ] 차트의 5개 표준 파일 역할을 안다 (`Chart.yaml`, `values.yaml`, `templates/_helpers.tpl`, `templates/deployment.yaml`, `templates/service.yaml`)
- [ ] `helm template` 으로 렌더 결과를 미리 본다
- [ ] values 오버라이드 (`-f`, `--set`) 방식을 안다

## 1. 미리 만들어진 차트 살펴보기

본 모듈 폴더의 [`charts/order-service/`](./charts/order-service/) 가 그것입니다.

```bash
cd charts/order-service
ls -la
ls templates/
```

기대:
```
Chart.yaml
values.yaml
.helmignore
templates/
  _helpers.tpl
  deployment.yaml
  service.yaml
  hpa.yaml
  ingress.yaml
```

## 2. lint

```bash
helm lint .
```

기대:
```
==> Linting .
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed
```

## 3. 템플릿 렌더 미리보기 (배포 X)

```bash
helm template demo . --set image.repository=test/order-service
```

기대: Deployment + Service 매니페스트가 출력됨. `demo-order-service` 가 fullname.

다양한 values를 주면서 비교:
```bash
helm template demo . --set image.repository=test/order-service --set replicaCount=5
helm template demo . --set image.repository=test/order-service --set autoscaling.enabled=true
helm template demo . --set image.repository=test/order-service --set ingress.enabled=true
```

## 4. 필수 값 누락 시 에러

```bash
helm template demo .            # image.repository 미지정
```

기대:
```
Error: execution error at (.../templates/deployment.yaml): image.repository is required
```

`{{ required "..." .Values.image.repository }}` 문법으로 강제 가능.

## 5. 실제 EKS에 dry-run 설치

ECR에 order-service 이미지가 푸시되어 있다고 가정. ([`00-prerequisites/scripts/ecr-push-all.sh`](../../00-prerequisites/scripts/ecr-push-all.sh))

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2
REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/eks-study/order-service"

helm install demo . \
  --set image.repository=$REPO \
  --set image.tag=latest \
  --dry-run --debug \
  | head -80
```

## 6. 실제 설치

```bash
helm install demo . \
  --set image.repository=$REPO \
  --set image.tag=latest \
  --namespace demo --create-namespace

helm list -A
kubectl get deploy,svc,pod -n demo
```

## 7. 업그레이드

values 일부만 변경:
```bash
helm upgrade demo . \
  --set image.repository=$REPO \
  --set replicaCount=4 \
  -n demo
```

```bash
kubectl get pods -n demo --watch
```

기대: replicas가 2 → 4로.

## 8. 이력 / 롤백

```bash
helm history demo -n demo
helm rollback demo 1 -n demo
helm history demo -n demo            # 새 revision으로 롤백 기록 추가
```

## 9. 정리

```bash
helm uninstall demo -n demo
kubectl delete ns demo
```

## 학습 확인 질문

1. `helm template` 과 `helm install --dry-run` 의 차이점은?
2. `helm rollback` 은 어느 revision으로 되돌리는가? 새 revision을 만드는가, 아니면 이전 revision 자체를 활성화하는가?
3. `values.yaml` 의 값이 `--set` CLI보다 우선순위가 높을까?

다음: [mini-project.md](./mini-project.md)
