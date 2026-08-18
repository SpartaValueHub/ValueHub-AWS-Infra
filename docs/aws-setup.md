# AWS Prod 체크리스트 (ValueHub)

콘솔에서 진행해도 됩니다. (이 PC에 AWS CLI가 아직 없을 수 있음)

## 1. 공통

- Region: `ap-northeast-2` (서울) 권장
- VPC 하나, Apps EC2와 DB EC2는 **같은 VPC / 서로 통신 가능한 서브넷**
- Key pair 생성 → `.pem` 안전하게 보관 (Git 금지)

## 2. 보안 그룹

### SG-Apps

| Type | Port | Source | 용도 |
|------|------|--------|------|
| SSH | 22 | 내 IP (또는 VPN) | 관리 |
| Custom TCP | 8000 | 0.0.0.0/0 또는 CloudFront/ALB | Gateway (Vercel → API) |

나중에 HTTPS면 ALB 443만 공용, 8000은 ALB SG만 허용 권장.

### SG-DB

| Type | Port | Source | 용도 |
|------|------|--------|------|
| SSH | 22 | 내 IP | 관리 |
| MySQL | 3306 | **SG-Apps만** | Apps → MySQL |
| Custom TCP | 27017 | **SG-Apps만** | Apps → Mongo |

DB를 인터넷에 열지 마세요.

## 3. EC2

| Name | Type | AMI | SG | 비고 |
|------|------|-----|-----|------|
| valuehub-apps | t3.large | Ubuntu 22.04 | SG-Apps | Docker Compose 앱 |
| valuehub-db | t3.medium | Ubuntu 22.04 | SG-DB | MySQL + Mongo |

각 인스턴스에 **Elastic IP** 연결.

- Apps EIP → Vercel `NEXT_PUBLIC_API_URL=http://<APPS_EIP>:8000` (HTTPS 전 임시)
- DB EIP → 관리용; 앱 설정에는 **Private IP** 사용

## 4. EC2 최초 세팅

### DB

```bash
# SSH 후
curl -fsSL https://raw.githubusercontent.com/SpartaValueHub/ValueHub-AWS-Infra/main/scripts/bootstrap-db-ec2.sh | bash
# 또는 레포 clone 후
bash scripts/bootstrap-db-ec2.sh
```

`.env`에서 `MONGODB_ADVERTISE_HOST=<DB private IP>` 설정 후:

```bash
cd /opt/valuehub-aws-infra
docker compose -f compose.prod-db.yml --env-file .env up -d
```

### Apps

```bash
bash scripts/bootstrap-apps-ec2.sh
```

`.env`에서 `MYSQL_HOST` / `MONGODB_HOST` = DB private IP, 시크릿·JWT 배치 후:

```bash
docker compose -f compose.prod-apps.yml --env-file .env up -d
```

## 5. GitHub Secrets (이 레포)

Settings → Secrets and variables → Actions:

| Name | 값 |
|------|-----|
| `APPS_EC2_HOST` | Apps Elastic IP |
| `APPS_EC2_USER` | `ubuntu` |
| `APPS_EC2_SSH_KEY` | 배포용 private key 전체 |

Apps EC2 `~/.ssh/authorized_keys`에 해당 공개키 등록.

## 6. 이미지 태그

Compose 기본 태그: `byeonghyunchoi/valuehub-*:prod`  

각 서비스 레포 CI에서 `:prod` 이미지를 Docker Hub에 push해야 Apps EC2 pull이 성공합니다.  
아직 `:prod`가 없으면 임시로 `.env`의 `IMAGE_TAG=dev`로 검증 가능 (운영 전용 태그로 바꾸는 것 권장).

## 7. Vercel

- `NEXT_PUBLIC_API_URL` (또는 팀에서 쓰는 API base env) = `http://<Apps EIP>:8000`
- Auth CORS: Apps `.env`의 `AUTH_ALLOWED_ORIGINS`에 Vercel URL 포함

## 8. Apps EC2 루트 디스크 증설

Docker 이미지가 쌓이면 `/` 가 8GB에서 100%가 된다. prune만으로는 부족하면 **EBS 크기를 늘린 뒤 OS에서 파일시스템을 확장**한다. (스왑과 무관)

대상: `i-0cc2c7df37a02b606` / `ap-northeast-2` / 권장 30GB

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
