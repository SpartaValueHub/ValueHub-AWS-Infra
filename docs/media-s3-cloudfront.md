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

## 스모크 테스트

- [x] S3 `put-object` (예: `health/smoke-*.txt`) 성공
- [x] CloudFront GET → **200** (본문 확인)
- S3 익명 직접 URL은 private라 실패하는 것이 정상

## Chat 연동 확인 (2026-08-25)

| 항목 | 결과 |
| --- | --- |
| EC2 Role `s3:PutObject` (`chat/` 포함 버킷 전체) | OK |
| CloudFront `chat/*` GET | OK (path 제한 없음) |
| S3 CORS (FE Presigned PUT + Content-Type) | OK — `AllowedOrigins: *`, Methods GET/PUT/HEAD |
| Key 규칙 | 스펙을 Chat 기준으로 맞춤: `chat/{yyyy}/{MM}/{dd}/{uuid}.{ext}` |

## Member / Product-Post Presign E2E (2026-08-25)

| Step | Member | Product-Post (listing) |
| --- | --- | --- |
| env (`S3_BUCKET`, `CLOUDFRONT_BASE_URL`) | OK (compose 재반영 후) | OK |
| Presign API | 200 | 200 |
| s3Key | `profiles/{memberUuid}/...` | `posts/{memberUuid}/...` |
| S3 PUT | 200 | 200 |
| CloudFront GET | 200 | 200 |

참고: CD로 서비스만 recreate 하면 EC2 compose에 `x-media-env`가 빠질 수 있음 → Infra compose를 EC2에 유지해야 함.

## 다음

1. ~~Apps EC2 `.env`에 실 `S3_BUCKET` / `CLOUDFRONT_BASE_URL` 반영~~ ✅ (+ compose `x-media-env`로 MSA 주입, Access Key는 EC2에 넣지 않음·Instance Role 사용)
2. MSA Presigned 업로드·삭제 API — 구현 가이드: [media-api-spec.md](./media-api-spec.md) (글·프로필·채팅, **5MB**)  
3. (선택) 커스텀 도메인 `img.*` + ACM
