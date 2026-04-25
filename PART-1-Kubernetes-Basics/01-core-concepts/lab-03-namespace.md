# Lab 03 — Namespace 격리 시연

## 학습 확인 포인트

- [ ] 같은 이름의 리소스가 다른 NS에서는 충돌 없이 존재 가능함을 확인했다
- [ ] NS 간 통신 방법(짧은 이름 vs FQDN)을 안다
- [ ] `kubectl config set-context --current --namespace` 로 기본 NS를 바꿔봤다

## 1. Namespace 만들기

```bash
kubectl apply -f manifests/namespace.yaml
kubectl get ns
```

기대: `lab-team-a`, `lab-team-b` 두 개 추가됨.

## 2. 같은 이름의 Deployment를 두 NS에 배포

```bash
# team-a
kubectl apply -n lab-team-a -f manifests/deployment.yaml

# team-b
kubectl apply -n lab-team-b -f manifests/deployment.yaml

kubectl get deploy -A | grep web
```

기대:
```
lab-team-a    web    3/3   3   3   30s
lab-team-b    web    3/3   3   3   25s
```

→ **같은 이름** `web` 이지만 충돌 없이 양쪽에 존재.

## 3. 기본 NS 바꿔보기

```bash
kubectl config set-context --current --namespace=lab-team-a
kubectl get pods       # team-a의 Pod만 보임

kubectl config set-context --current --namespace=lab-team-b
kubectl get pods       # team-b의 Pod만 보임

kubectl config set-context --current --namespace=default
```

## 4. Service 만들고 NS 간 호출 시도

team-a에 Service 추가:
```bash
kubectl create service clusterip web -n lab-team-a --tcp=80:80
```

디버그 Pod 띄우기 (같은 NS에서):
```bash
kubectl run -it --rm dbg --image=alpine -n lab-team-a -- sh
# 안에서:
apk add --no-cache curl
curl http://web/        # 짧은 이름 OK
exit
```

같은 디버그 Pod를 다른 NS에서 띄워서 호출:
```bash
kubectl run -it --rm dbg --image=alpine -n lab-team-b -- sh
# 안에서:
apk add --no-cache curl

# 짧은 이름은 자기 NS의 web을 찾기 때문에 → team-b의 web으로 감
curl http://web/

# team-a의 web에 가려면 FQDN
curl http://web.lab-team-a.svc.cluster.local/

exit
```

> **결론**: 같은 NS면 짧은 이름, 다른 NS면 FQDN(`<svc>.<ns>.svc.cluster.local`).

## 5. 리소스를 NS 단위로 일괄 정리

```bash
kubectl delete ns lab-team-a lab-team-b
```

`kubectl delete ns <name>` 만으로 그 NS 안의 모든 리소스가 삭제됩니다 → **격리의 또 다른 효과**.

## 학습 확인 질문

1. Node, PersistentVolume, ClusterRole 은 Namespace로 격리될까?
2. 같은 NS의 다른 Service에 접근하는 짧은 이름 형태는?
3. `kubectl delete ns my-ns` 의 위험성을 한 가지 들어보세요.

다음: [quiz.md](./quiz.md)
