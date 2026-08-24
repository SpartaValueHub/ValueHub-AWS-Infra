# S3 + CloudFront (미디어) 세팅 진행 로그

> 실값(버킷명, Distribution ID, 도메인, Access Key)은 git에 올리지 않는다.  
> 로컬: `secrets/media-app.env` / 예시: `env/media-app.env.example`  
> 흐름·아키텍처: [media-architecture.md](./media-architecture.md)

리전 예: `ap-northeast-2` / profile 예: `valuehub`

## 진행 상태

| Step | 내용 | 상태 |
| --- | --- | --- |
| 0 | 관리 그룹에 S3 / CloudFront FullAccess | ✅ |
| 1 | S3 버킷 private + CORS + 암호화 + 버전 | ✅ |
| 2 | CloudFront + OAC + 버킷 정책 | ✅ Deployed |
| 3 | IAM Policy / EC2 Role·Profile / media-app 유저 | ✅ |
| 4 | 아키텍처·흐름 문서 | ✅ `media-architecture.md` |

---

## 결과 요약 (예시)

| 항목 | 예시 |
| --- | --- |
| Bucket | `valuehub-media-<env>-<unique>` |
| CloudFront | `EXXXXXXXXXXXXX` / `dxxxxxxxxxxxx.cloudfront.net` |
| OAC | `EXXXXXXXXXXXXX` |
| EC2 Role | `valuehub-apps-ec2-role` → Apps `i-xxxxxxxxxxxxxxxxx` |
| IAM User | `valuehub-media-app` (키: `secrets/media-app.env`) |

조회 URL 예: `https://<cloudfront-domain>/<object-key>`
