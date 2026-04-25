# frontend

Go `html/template` 기반 SSR 프론트엔드. 시나리오 앱 데모 랜딩 페이지.

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `PORT` | `8080` | HTTP 리스너 포트 |

## 로컬 실행

```bash
go run .
# http://localhost:8080 접속
```

## 테스트

```bash
go test ./...
```

## 도커 빌드 (scenarios/ 루트에서)

```bash
docker build -t eks-study/frontend:latest -f frontend/Dockerfile ..
```
