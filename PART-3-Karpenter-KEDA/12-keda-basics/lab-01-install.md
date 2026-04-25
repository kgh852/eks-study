# Lab 01 — KEDA 설치

## 1. Helm 설치

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm install keda kedacore/keda \
  --namespace keda --create-namespace \
  --version 2.x.x \
  --set podIdentity.aws.irsa.enabled=true \
  --wait
```

## 2. 검증

```bash
kubectl get pods -n keda
```

기대:
```
NAME                                                   READY   STATUS
keda-admission-webhooks-xxx                            1/1     Running
keda-operator-xxx                                      1/1     Running
keda-operator-metrics-apiserver-xxx                    1/1     Running
```

## 3. CRD 확인

```bash
kubectl get crd | grep keda
```

기대:
```
clustertriggerauthentications.keda.sh
scaledjobs.keda.sh
scaledobjects.keda.sh
triggerauthentications.keda.sh
```

## 4. 로그 확인

```bash
kubectl logs -n keda -l app=keda-operator --tail=20
```

## 5. KEDA 메트릭 API 등록 확인

KEDA 가 K8s 의 external metrics API 에 등록되어 HPA 가 사용 가능:
```bash
kubectl get apiservices | grep external.metrics
```

기대:
```
v1beta1.external.metrics.k8s.io   keda/keda-operator-metrics-apiserver  True
```

## 6. 학습 확인 질문

1. KEDA 가 만든 metrics-server (apiservice) 의 역할은?
2. Helm 설치 시 `podIdentity.aws.irsa.enabled=true` 옵션은 무엇을 가능하게 하는가?
3. KEDA Operator 와 metrics-apiserver 가 분리된 이유는?

다음: [lab-02-cpu-scaler.md](./lab-02-cpu-scaler.md)
