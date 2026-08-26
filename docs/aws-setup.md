# AWS / 배포 셋업 (ValueHub)

현재(2026-08) 기준 **운영에 올라간 구조**와 최초 세팅·배포 흐름을 정리한다.  
상세 CI/CD·환경변수는 [cicd-flow.md](./cicd-flow.md), [env-flow.md](./env-flow.md) 참고.

---

## 1. 현재 구성 요약

| 구분 | 역할 | 인스턴스 | 스펙 | Elastic IP | Private IP |
| --- | --- | --- | --- | --- | --- |
| **Apps EC2** | Eureka, Gateway, 전 MSA, Redis, Kafka | `i-0cc2c7df37a02b606` | t3.large | `54.116.150.139` | `172.31.6.86` |
| **DB EC2** | MySQL 8.4 + MongoDB 7 (단일 노드 RS) | `i-00753b29433e6351c` | t3.medium | `52.78.72.232` | `172.31.8.143` |

- 리전: `ap-northeast-2` (서울)
- AWS 프로필/계정: `valuehub` / `471112928396`
- 키페어: `valuehub-aws-prod` (로컬 PEM: `.valuehub-aws-prod.pem`, **Git 금지**)
- Apps SG: `sg-095cc58b5a43c744b`
- DB SG: `sg-023aefc5e5868a2f5`
- 원격 경로 (양쪽 EC2): `/opt/valuehub-aws-infra`
- Compose: `compose.prod-apps.yml` / `compose.prod-db.yml`
- Docker Hub: **`p4rksk1611/valuehub-*`**, 태그 기본 **`prod`**
- API 도메인: `api.valuehub.art` → Apps EIP (HTTPS 미적용, 테스트는 `:8000`)

---

## 2. 배포 흐름 (누가 뭘 하는지)

### 2-1. 서비스 자동 배포 (일상)

```text
개발자: 서비스 레포 main 또는 develop 푸시
    ↓
GitHub Actions (Deploy AWS)  — 빌드는 Actions runner가 수행
    ├─ CI: jar/Docker 빌드 → Docker Hub push
    │     IMAGE_NAME=p4rksk1611/valuehub-<서비스>
    │     IMAGE_TAG=prod (+ git sha)
    └─ CD: SSH → Apps EC2
          cd /opt/valuehub-aws-infra
          docker compose -f compose.prod-apps.yml --env-file .env pull <서비스>
          docker compose ... up -d --no-deps <서비스>
```

| 주체 | 역할 |
| --- | --- |
| 개발자 | 코드 푸시 (트리거) |
| GitHub Actions | 빌드 + Hub push + SSH 배포 |
| Docker Hub (`p4rksk1611`) | 이미지 저장소 |
| Apps EC2 | 해당 서비스 컨테이너만 교체 |
| DB EC2 | **이 단계에서 배포하지 않음** (이미 떠 있는 DB에 Apps가 private로 접속) |

- 워크플로 원본(복붙용): `templates/deploy-aws.yml`  
  → 실제 동작은 **각 서비스 레포** `.github/workflows/deploy-aws.yml`
- Infra 템플릿만 고쳐도 서비스 레포에 **자동 반영되지 않음**

### 2-2. DB는 어떻게 올라가나

- DB는 서비스 CI/CD와 **별개**. DB EC2에서 Compose로 MySQL/Mongo **공식 이미지** 기동.
- `scripts/mysql-init-schemas.sql`은 MySQL **`mysql-data` 볼륨이 비어 있을 때 최초 1회**만 실행 → `auth_db` 등 **DB 이름만** 생성 (테이블 아님).
- 테이블은 각 MSA가 기동할 때 JPA `ddl-auto` 등으로 Entity 기준 반영 (서비스별 설정 상이).
- Kafka는 **Apps EC2** (`compose.prod-apps.yml`). 토픽은 `kafka-init`이 기동 때 생성. 계약은 [kafka.md](./kafka.md).

### 2-3. 런타임 API (배포와 별개)

```text
FE / Swagger → Gateway :8000 → Eureka :8761 + MSA → DB private (MySQL :3306 / Mongo :27017). Kafka는 Apps 내부 `kafka:19092`.
```

| 용도 | URL |
| --- | --- |
| Gateway Health | http://54.116.150.139:8000/health 또는 http://api.valuehub.art:8000/health |
| 통합 Swagger | http://54.116.150.139:8000/swagger-ui/index.html |
| Eureka | http://54.116.150.139:8761 |

---

## 3. 보안 그룹

### SG-Apps

| Type | Port | Source | 용도 |
| --- | --- | --- | --- |
| SSH | 22 | 관리 IP | 관리 / Actions 배포 |
| Custom TCP | 8000 | `0.0.0.0/0` (현재 팀 테스트) | Gateway |
| Custom TCP | 8761 | `0.0.0.0/0` (현재 팀 테스트) | Eureka 대시보드 |

Kafka·Kafka UI는 `127.0.0.1`만 바인딩. SG에 9092/8080을 열지 말 것. UI는 SSH 터널:  
`ssh -i .valuehub-aws-prod.pem -L 8080:127.0.0.1:8080 ubuntu@54.116.150.139`

나중에 HTTPS면 ALB/Nginx 443만 공용, 8000·8761은 축소 권장.

### SG-DB

| Type | Port | Source | 용도 |
| --- | --- | --- | --- |
| SSH | 22 | 관리 IP | 관리 / Workbench 터널 |
| MySQL | 3306 | **SG-Apps만** | Apps → MySQL |
| Custom TCP | 27017 | **SG-Apps만** | Apps → Mongo |

DB를 인터넷에 직접 열지 말 것. Workbench는 SSH 터널 권장  
예: `ssh -i .valuehub-aws-prod.pem -L 3307:127.0.0.1:3306 ubuntu@52.78.72.232` → Workbench `127.0.0.1:3307`

---

## 4. EC2 최초 세팅

Apps / DB는 **같은 VPC·통신 가능한 서브넷**, 각각 Elastic IP 연결.

### 4-1. DB EC2

```bash
# SSH 후
bash scripts/bootstrap-db-ec2.sh
# 또는
curl -fsSL https://raw.githubusercontent.com/SpartaValueHub/ValueHub-AWS-Infra/main/scripts/bootstrap-db-ec2.sh | bash
```

`.env` (`env/db.env.example` 복사):

- `MYSQL_ROOT_PASSWORD`, `MONGODB_USERNAME` / `MONGODB_PASSWORD`
- `MONGODB_ADVERTISE_HOST=<DB private IP>` (예: `172.31.8.143`)

```bash
cd /opt/valuehub-aws-infra
docker compose -f compose.prod-db.yml --env-file .env up -d
```

### 4-2. Apps EC2

```bash
bash scripts/bootstrap-apps-ec2.sh
```

`.env` (`env/apps.env.example` 복사):

- `MYSQL_HOST` / `MONGODB_HOST` = **DB private IP**
- `IMAGE_TAG=prod`
- JWT / `AUTH_ALLOWED_ORIGINS` 등

```bash
cd /opt/valuehub-aws-infra
docker compose -f compose.prod-apps.yml --env-file .env up -d
```

실값 `.env`는 git에 올리지 않는다. 배포(CD)는 **이미지·컨테이너만** 바꾸고 `.env`는 수정하지 않는다.

---

## 5. GitHub 설정

### 5-1. 각 서비스 레포 (Deploy AWS) — 필수

**Secrets**

| Name | 값 |
| --- | --- |
| `APPS_EC2_HOST` | `54.116.150.139` |
| `APPS_EC2_USER` | `ubuntu` |
| `APPS_EC2_SSH_KEY` | 배포용 private key |
| `DOCKERHUB_USERNAME` | `p4rksk1611` |
| `DOCKERHUB_TOKEN` | Docker Hub Access Token |

**Variables** (서비스마다 다름, 예시는 Auth)

| Name | 예 |
| --- | --- |
| `IMAGE_NAME` | `p4rksk1611/valuehub-auth` |
| `COMPOSE_SERVICE` | `auth` (compose 서비스키) |
| `IMAGE_TAG` | `prod` |

현재 14개 서비스 `IMAGE_NAME`는 모두 **`p4rksk1611/valuehub-*`** 로 통일.

| 레포 | IMAGE_NAME | COMPOSE_SERVICE |
| --- | --- | --- |
| Auth-Service | `p4rksk1611/valuehub-auth` | `auth` |
| Chat-Service | `p4rksk1611/valuehub-chat` | `chat` |
| Gateway-Service | `p4rksk1611/valuehub-gateway` | `gateway` |
| Discovery-Service | `p4rksk1611/valuehub-discovery` | `discovery` |
| Member-Service | `p4rksk1611/valuehub-member` | `member` |
| Category-Service | `p4rksk1611/valuehub-category` | `category` |
| Product-Post-Service | `p4rksk1611/valuehub-listing` | `listing` |
| Member-Regions-Service | `p4rksk1611/valuehub-member-regions` | `member-regions` |
| Reports-Service | `p4rksk1611/valuehub-reports` | `reports` |
| Reservations-Service | `p4rksk1611/valuehub-reservations` | `reservations` |
| Reviews-Service | `p4rksk1611/valuehub-reviews` | `reviews` |
| Notifications-Service | `p4rksk1611/valuehub-notifications` | `notifications` |
| Premium-Plans-Service | `p4rksk1611/valuehub-premium-plans` | `premium-plans` |
| Bo-Service | `p4rksk1611/valuehub-bo` | `bo` |

### 5-2. Infra 레포 (`ValueHub-AWS-Infra`)

Infra 워크플로 `Deploy Apps (Prod)`: compose 등을 Apps EC2에 scp 후 `docker compose up` (서비스 이미지 빌드와 별개).

필요 시 Secrets: `APPS_EC2_HOST` / `APPS_EC2_USER` / `APPS_EC2_SSH_KEY`

---

## 6. Compose가 붙는 DB 이름 (Apps)

`compose.prod-apps.yml`의 `SPRING_DATASOURCE_URL` 기준 (호스트는 `.env`의 `MYSQL_HOST`):

| Compose 서비스 | MySQL DB |
| --- | --- |
| auth | `auth_db` |
| member | `member_db` |
| category | `category_db` |
| listing (Product-Post) | `listing_db` |
| member-regions | `member_regions_db` |
| reports | `reports_db` |
| reservations | `reservations_db` |
| reviews | `reviews_db` |
| notifications | `notifications_db` |
| premium-plans | `premium_plans_db` |
| bo | `bo_db` |
| chat | `chat_db` (+ Mongo `chatting_db`) |

Kafka: 같은 compose의 `kafka:19092`. `member` / `listing` / `reservations` / `chat`에 `SPRING_KAFKA_BOOTSTRAP_SERVERS` 고정 주입. 토픽 계약은 [kafka.md](./kafka.md).

Workbench에서 DB 이름을 바꿔도, **compose URL을 같이 안 바꾸면** 앱은 예전 이름을 본다.

---

## 7. FE (Vercel)

- Eureka 등록 불필요. **Gateway URL만** 필요.
- 예: `NEXT_PUBLIC_API_URL=http://api.valuehub.art:8000` (또는 Apps EIP `:8000`)
- CORS: Auth는 `AUTH_ALLOWED_ORIGINS`, Gateway는 코드/설정에 origin 추가 필요할 수 있음
- HTTPS(`443`)는 아직 미구성 → 당분간 `:8000`으로 테스트

---

## 8. Apps EC2 루트 디스크 증설

Docker 이미지가 쌓이면 `/` 가 8GB에서 100%가 된다. prune만으로 부족하면 **EBS를 늘린 뒤 OS에서 파일시스템을 확장**한다. (스왑과 무관)

대상: `i-0cc2c7df37a02b606` / `ap-northeast-2` / 권장 30GB  
관련 이슈: #8

### 8-1. AWS 콘솔

1. EC2 → 인스턴스 `i-0cc2c7df37a02b606` → Storage → 루트 볼륨 클릭
2. Actions → Modify volume → Size **30** GiB → Modify
3. 상태가 `optimizing` / `in-use` 가 될 때까지 대기 (인스턴스 재시작 보통 불필요)

### 8-2. SSH 후 파일시스템 확장 (Ubuntu)

```bash
lsblk
sudo growpart /dev/nvme0n1 1
sudo resize2fs /dev/nvme0n1p1
df -h /
```

`lsblk`에서 루트 디바이스/파티션 번호가 다르면 그에 맞춘다. XFS면 `resize2fs` 대신 `sudo xfs_growfs /` .

성공 시 `df -h /` 의 Size가 ~30G, Use%가 크게 내려간다.

---

## 9. 관련 문서

| 문서 | 내용 |
| --- | --- |
| [cicd-flow.md](./cicd-flow.md) | CI/CD·시퀀스·서비스 목록 |
| [env-flow.md](./env-flow.md) | `.env` 런타임 주입 |
| [kafka.md](./kafka.md) | Kafka 토픽·페이로드 |
| `templates/deploy-aws.yml` | 서비스 Deploy AWS 템플릿 |
| `env/apps.env.example` / `env/db.env.example` | env 이름 예시 |
