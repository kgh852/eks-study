# user-service

gRPC 기반 사용자 CRUD 서비스. **서비스 간 통신** 학습용 (Part 2 09 모듈에서 order-service가 호출하는 형태로 사용 예정).

## 인터페이스

`proto/user.proto` 참고:

```proto
service UserService {
  rpc GetUser(GetUserRequest) returns (User);
  rpc CreateUser(CreateUserRequest) returns (User);
}
```

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `GRPC_PORT` | `50051` | gRPC 리스너 포트 |

## 로컬 실행

```bash
go run .
```

## 호출 예시 (`grpcurl` 필요)

```bash
brew install grpcurl
grpcurl -plaintext -d '{"name":"finn","email":"f@x.io"}' \
  localhost:50051 user.v1.UserService/CreateUser
```

## 테스트

```bash
go test ./...
```

## proto 코드 재생성

```bash
PATH=$PATH:$(go env GOPATH)/bin protoc \
  --go_out=. --go_opt=paths=source_relative \
  --go-grpc_out=. --go-grpc_opt=paths=source_relative \
  proto/user.proto
mv proto/user.pb.go proto/userv1/
mv proto/user_grpc.pb.go proto/userv1/
```
