# ValueHub-AWS-Infra

ValueHub **AWS 운영(Prod) 배포** 전용 저장소입니다.  
개발 노트북용 `ValueHub-Infra`와 분리되어 있습니다.

## 아키텍처

```text
[사용자] → [Vercel Frontend]
                 │
                 ▼  HTTPS / API
         ┌───────────────────────┐
         │  Apps EC2 (t3.large)  │  ← Elastic IP
         │  Gateway :8000        │
         │  Discovery (Eureka)   │
         │  Auth, Member, Chat…  │
         │  Redis                │
         └───────────┬───────────┘
                     │ private / SG
         ┌───────────▼───────────┐
         │  DB EC2 (t3.medium)   │  ← Elastic IP (관리용, 앱은 private IP 권장)
         │  MySQL (스키마 분리)   │
         │  MongoDB (chat)       │
         └───────────────────────┘
```

| 구분 | 역할 |
|------|------|
| Apps EC2 | 마이크로서비스 + Redis + Docker Compose |
| DB EC2 | MySQL + MongoDB만 |
| 이 레포 | Prod compose, env 예시, EC2 부트스트랩, GitHub Actions |
| 각 서비스 레포 | 이미지 빌드 → Docker Hub (`:prod` 태그) |
| Vercel | 프론트엔드 (`NEXT_PUBLIC_API_URL` → Gateway Elastic IP/도메인) |

## 디렉터리

```text
compose.prod-apps.yml   # Apps EC2
compose.prod-db.yml     # DB EC2
env/
  apps.env.example
  db.env.example
scripts/
  bootstrap-apps-ec2.sh
  bootstrap-db-ec2.sh
.github/workflows/
  deploy-apps.yml       # main push → Apps EC2 배포
docs/
  aws-setup.md          # EC2 / SG / EIP 체크리스트
```

## 배포 흐름

1. 서비스 레포에서 `main` 빌드 → `byeonghyunchoi/valuehub-<service>:prod` push  
2. 이 레포 `main` 변경(또는 수동 workflow) → Actions가 Apps EC2에 SSH  
3. EC2에서 `docker compose pull` + `up -d`

DB EC2는 자주 안 바꿉니다. 최초 `compose.prod-db.yml`로 기동 후 스키마/볼륨 유지.

## 빠른 시작 (순서)

1. [docs/aws-setup.md](./docs/aws-setup.md) 따라 EC2 2대 + Elastic IP + 보안그룹  
2. 각 EC2에서 bootstrap 스크립트 실행  
3. `env/*.example` → EC2의 `.env`로 복사 후 비밀번호·호스트 채우기  
4. DB EC2: `docker compose -f compose.prod-db.yml --env-file .env up -d`  
5. Apps EC2: DB private IP를 `.env`에 넣고 `compose.prod-apps.yml` up  
6. GitHub Secrets 등록 후 Actions로 자동 배포

자세한 Secrets 목록은 `docs/aws-setup.md`를 보세요.
