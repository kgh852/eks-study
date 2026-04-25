# Lab 01 — RBAC 으로 제한된 SA 만들기

## 학습 확인 포인트

- [ ] ServiceAccount 가 자체 토큰을 가지고 있음을 확인했다
- [ ] Role/RoleBinding 으로 권한이 부여되는 흐름을 봤다
- [ ] 권한 없는 행동을 시도했을 때 `Forbidden` 응답을 받아봤다

## 1. RBAC 리소스 적용

```bash
kubectl apply -f manifests/rbac.yaml
kubectl get sa,role,rolebinding,pod
```

## 2. 권한 점검 (`auth can-i`)

```bash
SA="system:serviceaccount:default:pod-reader-sa"
kubectl auth can-i list pods --as=$SA              # yes
kubectl auth can-i get pods --as=$SA               # yes
kubectl auth can-i delete pods --as=$SA            # no
kubectl auth can-i list deployments --as=$SA       # no
kubectl auth can-i list pods -n kube-system --as=$SA  # no (다른 NS)
```

## 3. Pod 안에서 직접 API 호출

`rbac-test` Pod는 `pod-reader-sa` 로 떠 있습니다. kubectl 컨테이너 안에서 직접 호출:

```bash
kubectl exec -it rbac-test -- sh

# 안에서 — Pod의 자동 마운트된 토큰을 kubectl이 사용
kubectl get pods                              # 성공
kubectl logs rbac-test                        # 성공 (자기 로그)
kubectl get deployments                       # 실패: Forbidden
kubectl get pods -n kube-system               # 실패: Forbidden
kubectl delete pod rbac-test                  # 실패: Forbidden

exit
```

## 4. Pod 내부의 토큰 위치

```bash
kubectl exec -it rbac-test -- ls /var/run/secrets/kubernetes.io/serviceaccount/
```

기대:
```
ca.crt
namespace
token
```

`token` 이 SA의 JWT. 자동으로 마운트되어 in-cluster K8s API 호출 시 사용됩니다.

> EKS 1.24+ 에서는 토큰이 **bound token** 으로 자동 갱신 (옛날엔 Secret으로 영구 토큰).

## 5. 권한 추가하기 (실험)

`pod-reader` Role을 수정해 `delete` 추가:

```bash
kubectl edit role pod-reader
# rules.verbs 에 "delete" 추가
```

다시 시도:
```bash
kubectl exec -it rbac-test -- kubectl delete pod rbac-test
```

기대: 자기 자신을 지움. (Pod이 사라지므로 다음 명령은 새 Pod 생성 필요)

## 6. ClusterRole 시나리오

```bash
kubectl auth can-i list nodes --as=$SA      # no (cluster-scoped, ClusterRole 필요)

# ClusterRole + ClusterRoleBinding 추가 (학습용)
kubectl create clusterrole node-reader --verb=get,list --resource=nodes
kubectl create clusterrolebinding pod-reader-sa-node-reader \
  --clusterrole=node-reader \
  --serviceaccount=default:pod-reader-sa

kubectl auth can-i list nodes --as=$SA      # yes
```

## 7. 정리

```bash
kubectl delete -f manifests/rbac.yaml
kubectl delete clusterrole node-reader --ignore-not-found
kubectl delete clusterrolebinding pod-reader-sa-node-reader --ignore-not-found
```

## 학습 확인 질문

1. `kubectl auth can-i ... --as=<user>` 에서 `<user>` 부분에 ServiceAccount를 지정하는 형식은?
2. RoleBinding 으로 ClusterRole 을 참조할 수 있는가? 가능하면 어떤 효과?
3. EKS에서 IAM 사용자/역할이 K8s API 권한을 갖게 되는 추가 단계는? (ConfigMap aws-auth 또는 EKS Access Entries)

다음: [lab-02-helm-chart.md](./lab-02-helm-chart.md)
