# 이론 — Service & Networking

## 1. 왜 Service가 필요한가

Pod의 IP는 **짧은 수명**입니다. Pod가 재시작되면 IP가 바뀝니다. Pod에 직접 IP로 접속하는 건 깨지기 쉽습니다.

**Service 가 하는 일**:
1. **고정된 가상 IP** (ClusterIP) 제공
2. 라벨 셀렉터로 묶인 Pod들에게 **부하 분산**
3. **DNS 이름** 부여 (예: `my-svc.default.svc.cluster.local`)

```
Client (Pod) ──→ Service (ClusterIP 10.100.5.7)
                         │
                         ├──→ Pod-A (10.0.1.5)
                         ├──→ Pod-B (10.0.2.6)   ← Endpoints
                         └──→ Pod-C (10.0.3.7)
```

`Endpoints` 는 Service의 셀렉터에 매칭되는 Pod의 IP 목록입니다. Service를 만들면 자동으로 같이 만들어집니다.

---

## 2. Service 타입 4가지

### 2.1 ClusterIP (기본값)

- 클러스터 내부에서만 접근 가능한 가상 IP
- 외부 노출은 별도 (Ingress, port-forward, NodePort/LB)
- **거의 모든 Service의 기본**

```yaml
spec:
  type: ClusterIP    # 생략해도 동일
  selector:
    app: web
  ports:
    - port: 80           # Service 노출 포트
      targetPort: 8080   # Pod 컨테이너 포트
```

### 2.2 NodePort

- 모든 노드의 특정 포트(30000~32767)를 열어서 외부에서 노드 IP:포트로 접속 가능
- 단순하지만 운영에서 직접 쓰는 경우는 적음 (LB가 더 깔끔)
- 학습/디버깅용으로 유용

```yaml
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30080    # 생략하면 자동 할당
```

### 2.3 LoadBalancer

- 클라우드 공급자가 LB를 자동 프로비저닝 (AWS면 NLB)
- ClusterIP + NodePort 를 포함하면서, 그 위에 외부 LB 추가
- 인터넷 노출이 가장 단순한 방법
- **주의: 비용 발생** (시간당 약 0.0225 USD + 데이터)

```yaml
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 8080
```

EKS에서는 기본적으로 **CLB(Classic LB)** 가 만들어지지만, AWS Load Balancer Controller가 설치되어 있으면 어노테이션으로 NLB/ALB로 변경 가능 (Part 2에서 다룸).

### 2.4 ExternalName

- 클러스터 내 DNS에 외부 도메인을 CNAME으로 등록
- 예: `db.example.com` 을 `db` 라는 짧은 이름으로 호출 가능
- 거의 안 씀

```yaml
spec:
  type: ExternalName
  externalName: api.external.com
```

---

## 3. 어떤 타입을 언제 쓰나

| 시나리오 | 타입 |
|---------|------|
| 내부 마이크로서비스 간 통신 | ClusterIP |
| 외부 인터넷 노출 (간단) | LoadBalancer |
| 외부 인터넷 노출 (HTTP 라우팅 + TLS + 다중 도메인) | Ingress (뒤단은 ClusterIP) |
| 노드 IP로 빠르게 접근 (개발/디버그) | NodePort |
| 외부 시스템을 짧은 이름으로 | ExternalName |

**Best Practice**: 외부 노출이 필요한 모든 HTTP 트래픽은 **Ingress + ClusterIP** 조합. LoadBalancer Service는 비-HTTP (gRPC/TCP) 또는 단순 케이스에만.

---

## 4. CoreDNS — 클러스터 DNS

K8s 클러스터 안에서는 CoreDNS Pod가 떠 있습니다 (`kube-system` NS).

### 4.1 자동 생성되는 DNS 레코드

Service `my-svc` 를 NS `prod` 에 만들면:
- `my-svc.prod.svc.cluster.local` → ClusterIP A 레코드
- 같은 NS의 Pod에서는 짧게: `my-svc`
- 다른 NS의 Pod에서는: `my-svc.prod`

Pod 단위 DNS도 있지만 거의 안 씁니다 (StatefulSet의 Headless Service 케이스 정도).

### 4.2 검색 도메인

Pod의 `/etc/resolv.conf` 는 자동으로:
```
search <ns>.svc.cluster.local svc.cluster.local cluster.local
nameserver <CoreDNS의 ClusterIP>
```

→ `curl my-svc` 만 해도 search 도메인이 차례로 붙어가며 시도.

---

## 5. kube-proxy — 뒤에서 하는 일

ClusterIP는 **실제로 존재하지 않는 IP** 입니다. Pod가 ClusterIP로 패킷을 보내면 무엇이 그 패킷을 실제 Pod로 라우팅할까요?

→ **kube-proxy** (DaemonSet) 가 각 노드의 iptables/ipvs 룰을 관리해 패킷을 변환합니다.

```
Pod-X → 10.100.5.7 (ClusterIP)
   ↓
[노드의 iptables DNAT 룰]
   ↓
Pod-A (10.0.1.5) 또는 Pod-B 또는 Pod-C 중 임의로 라운드로빈
```

**EKS에서는 모드가 `iptables` 가 기본**. 대규모 클러스터(수천 Service)면 `ipvs` 모드가 효율적이지만 학습 단계에서는 무관.

> **EKS 1.30 이후**: Cilium 같은 eBPF 기반 솔루션을 쓰면 kube-proxy를 대체 가능 (advanced).

---

## 6. Ingress — HTTP 라우팅 레이어

### 6.1 Ingress vs Service

- **Service**: L4 (TCP/UDP). LB Service는 노드 IP로 트래픽을 받는 단순 분배.
- **Ingress**: L7 (HTTP/HTTPS). 호스트 이름, 경로 기반 라우팅 + TLS 종료.

### 6.2 Ingress 자체는 "설정"

Ingress 리소스는 **명세만** 합니다. 실제 트래픽 처리는 **Ingress Controller** 가 합니다.

K8s 표준에는 Ingress Controller가 없습니다. 별도 설치:
- **AWS Load Balancer Controller** (EKS) — Ingress를 ALB로 매핑
- nginx-ingress, traefik, contour, ...

### 6.3 예시

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
spec:
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-svc
                port: { number: 80 }
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-svc
                port: { number: 80 }
```

→ `https://app.example.com/api/*` 는 `api-svc` 로, 나머지는 `web-svc` 로.

> **본 모듈에서는** Ingress Controller 설치까지는 안 갑니다. Part 2의 06-vpc-cni-networking 에서 AWS LB Controller 설치하고 본격 사용.

---

## 7. 핵심 정리

```
[외부] → ALB (Ingress Controller가 만듦)
           │ (L7 라우팅)
           ▼
       Service (ClusterIP)  ← 안정된 내부 주소
           │ (kube-proxy DNAT)
           ▼
        Pod-A / Pod-B / Pod-C  ← 셀렉터로 묶인 Endpoints
           │ (CoreDNS로 이름 해석)
           ▼
       다른 Service / Pod
```

다음: [lab-01-clusterip.md](./lab-01-clusterip.md)
