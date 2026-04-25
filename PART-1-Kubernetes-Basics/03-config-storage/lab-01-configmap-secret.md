# Lab 01 — ConfigMap / Secret

## 학습 확인 포인트

- [ ] ConfigMap을 환경변수로/파일로 두 방법 모두 사용했다
- [ ] Secret과 ConfigMap의 사용법이 거의 같음을 확인했다
- [ ] ConfigMap을 변경하면 마운트된 파일은 자동 갱신, env는 갱신 안 되는 걸 봤다

## 1. 적용

```bash
kubectl apply -f manifests/configmap-secret.yaml
kubectl get cm,secret,pod
```

기대: `app-config` ConfigMap, `app-secret` Secret, `configdemo` Pod 모두 존재.

## 2. Pod 안에서 어떻게 보이는지 확인

```bash
kubectl logs configdemo
```

기대 (대략):
```
==== ENV ====
LOG_LEVEL=info
GREETING=Hello from ConfigMap!
API_KEY=super-secret-key-do-not-commit
DB_PASSWORD=pa$$w0rd

==== Mounted file (ConfigMap) ====
server {
  port = 8080
  mode = production
}

==== Mounted file (Secret) ====
super-secret-key-do-not-commit
```

→ 같은 ConfigMap이 환경변수와 파일 양쪽으로 주입됨.
→ Secret도 마찬가지.

## 3. 직접 들어가 확인

```bash
kubectl exec -it configdemo -- sh
# 안에서:
ls /etc/app
ls /etc/secret
cat /etc/app/app.conf
mount | grep /etc/app    # tmpfs 또는 fuse 형태로 마운트됨
```

## 4. ConfigMap 변경 → 마운트 파일 자동 갱신 확인

별도 터미널:
```bash
kubectl exec -it configdemo -- sh -c "watch -n2 cat /etc/app/app.conf"
```

원래 터미널:
```bash
kubectl edit cm app-config
# data.app.conf 의 port 를 8080 → 9090 로 변경, 저장
```

기대: 약 30 ~ 60초 후 watch 화면의 파일 내용이 갱신됨 (kubelet이 파일을 주기적으로 갱신).

## 5. ConfigMap 변경 → 환경변수는 갱신 **안 됨** 확인

```bash
kubectl exec -it configdemo -- env | grep GREETING
```

ConfigMap에서 GREETING 값을 바꿔도 위 명령은 옛 값 그대로. **Pod를 재시작해야 반영.**

```bash
kubectl delete pod configdemo
# Pod이 자동으로 안 살아남 (단일 Pod이라). 다시 적용:
kubectl apply -f manifests/configmap-secret.yaml
kubectl logs configdemo | grep GREETING
```

## 6. Secret을 stringData로 만든 이유

매니페스트 보기:
```bash
kubectl get secret app-secret -o yaml | yq '.data'
```

기대 (base64 인코딩된 값):
```yaml
API_KEY: c3VwZXItc2VjcmV0LWtleS1kby1ub3QtY29tbWl0
DB_PASSWORD: cGEkJHcwcmQ=
```

매니페스트에서 `stringData:` 로 적으면 K8s가 자동 base64 인코딩. `data:` 로 적으면 수동 인코딩 필요.

> ⚠️ Secret은 base64일 뿐 **암호화 아님**. RBAC으로 접근 제어하고, etcd 자체 암호화 켜야 진짜 보안.

## 7. Secret을 다루는 안전한 패턴 (참고)

매니페스트에 평문 비밀번호 두지 말 것. 옵션:
- `kubectl create secret generic ... --from-literal=...` 명령으로만 생성 (CI에서 환경변수로)
- Secrets Store CSI Driver + AWS Secrets Manager (Part 2~3)
- External Secrets Operator
- Sealed Secrets

## 8. 정리

```bash
kubectl delete -f manifests/configmap-secret.yaml
```

## 학습 확인 질문

1. `envFrom: [configMapRef: ...]` 와 `env: - valueFrom: configMapKeyRef:` 의 차이는?
2. ConfigMap을 파일로 마운트한 Pod이 hot-reload를 지원하지 않으면 어떻게 해야 갱신될까?
3. Secret을 git에 커밋해도 괜찮은 케이스가 있을까? (있다면 어떤 추가 도구 사용?)

다음: [lab-02-pv-pvc.md](./lab-02-pv-pvc.md)
