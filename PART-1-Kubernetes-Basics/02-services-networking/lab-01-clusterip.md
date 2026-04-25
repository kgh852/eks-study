# Lab 01 — ClusterIP + Endpoints 관찰

## 학습 확인 포인트

- [ ] Service 만들면 Endpoints가 자동 생성됨을 확인했다
- [ ] 라벨 셀렉터로 Pod와 Service가 묶이는 메커니즘을 봤다
- [ ] Pod 죽으면 Endpoints가 자동 갱신되는 걸 봤다

## 1. 배포

```bash
kubectl apply -f manifests/clusterip.yaml
kubectl get svc web -o wide
kubectl get endpoints web        # 또는 endpointslices
```

기대:
```
NAME   TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE   SELECTOR
web    ClusterIP   10.100.123.45    <none>        80/TCP    20s   app=web

NAME   ENDPOINTS                                AGE
web    10.0.1.21:80,10.0.2.15:80,10.0.3.8:80    20s
```

→ **3개 Pod의 IP가 자동 등록**되어 있음.

## 2. 클러스터 내부에서 호출

```bash
kubectl run -it --rm dbg --image=alpine -- sh
# 안에서:
apk add --no-cache curl
curl http://web/                     # 짧은 이름
curl http://web.default/             # NS 명시
curl http://web.default.svc.cluster.local/   # FQDN
exit
```

세 가지 모두 동일하게 nginx 페이지 반환.

## 3. 부하 분산 확인

호스트네임을 보여주는 작은 트릭:

```bash
kubectl exec -it deploy/web -- sh -c \
  "echo \"\$HOSTNAME\" > /usr/share/nginx/html/index.html"
```

(Pod마다 별도 명령이 필요한 경우라 위 명령은 한 Pod에만 적용됨. 더 깔끔한 방법:)

```bash
kubectl get pods -l app=web -o name | while read p; do
  kubectl exec $p -- sh -c "echo $p > /usr/share/nginx/html/index.html"
done
```

이제 부하 분산 확인:

```bash
kubectl run -it --rm dbg --image=alpine -- sh
apk add --no-cache curl
for i in 1 2 3 4 5 6; do curl -s http://web/ ; done
exit
```

기대: 매번 다른 Pod 이름 반환 (라운드 로빈에 가까운 분배).

## 4. Pod 죽이고 Endpoints 갱신 관찰

watch:
```bash
watch -n1 kubectl get endpoints web
```

다른 터미널:
```bash
kubectl get pods -l app=web
kubectl delete pod <web-xxx>          # 임의 1개
```

watch 화면: ENDPOINTS 칸에서 IP 한 개가 빠지고, 잠시 후 새 Pod의 IP로 채워짐.

## 5. 셀렉터 변경하면? (의도적 망가뜨리기)

```bash
kubectl patch svc web --type=json -p='[{"op":"replace","path":"/spec/selector","value":{"app":"nonexistent"}}]'
kubectl get endpoints web
```

기대: ENDPOINTS 가 비어버림 (`<none>`).

→ Service는 살아있지만 호출하면 응답 없음. 흔한 디버깅 시작점.

복구:
```bash
kubectl patch svc web --type=json -p='[{"op":"replace","path":"/spec/selector","value":{"app":"web"}}]'
```

## 학습 확인 질문

1. ClusterIP는 어디서 라우팅되는가? (커널 어떤 컴포넌트?)
2. Service의 selector를 바꾸지 않고 Endpoints를 직접 편집할 수도 있을까? 어떤 시나리오에서 필요할까?
3. `default` NS의 Pod가 `prod` NS의 `db` Service를 호출하려면 어떻게 해야 할까?

다음: [lab-02-nodeport-lb.md](./lab-02-nodeport-lb.md)
