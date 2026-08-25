# ValueHub 미디어 API 스펙 (MSA 구현 가이드)

> Infra의 S3 + CloudFront를 **각 서비스 API에서 어떻게 쓸지** 정리한 기준 문서.  
> 인프라/흐름: [media-architecture.md](./media-architecture.md)

실 버킷·CDN 도메인은 Apps EC2 `.env` / `secrets/media-app.env` 참고 (이 문서는 placeholder).

---

## 1. 공통 규칙

| 항목 | 규칙 |
| --- | --- |
| 저장 | S3 private 버킷 1개 |
| 조회 URL | `CLOUDFRONT_BASE_URL` + `/` + `s3_key` |
| **최대 용량** | **5MB (5 * 1024 * 1024 bytes)** — 글·프로필·채팅 **동일** |
| 허용 Content-Type (권장) | `image/jpeg`, `image/png`, `image/webp`, `image/gif` |
| DB 저장 | `s3_key` 필수 권장 + (선택) `image_url` = CloudFront URL |
| 업로드 경로 | **Presigned PUT** (클라이언트가 S3에 직접 PUT, CloudFront로 업로드하지 않음) |
| AWS 자격증명 | Apps EC2 **Instance Role** (Access Key를 컨테이너 env에 두지 않음) |

### 5MB 검증 (반드시 BE + 가능하면 S3)

1. **FE**: UX용 사전 체크 (우회 가능)  
2. **BE (Presigned 발급 시)**: 클라이언트가 보낸 `contentType` / `contentLength`(또는 size) 검사 → 5MB 초과면 400  
3. **S3 Presigned 조건**: `content-length-range` 1 ~ 5242880 (가능한 SDK/정책으로 강제)

---

## 2. S3 Key prefix (도메인 구분)

| 용도 | 담당 서비스 (권장) | Key 패턴 |
| --- | --- | --- |
| 게시글 이미지 | Product-Post (`listing`) | `posts/{postId또는uuid}/{uuid}.{ext}` |
| 프로필 이미지 | Member (또는 Auth) | `profiles/{userId}/{uuid}.{ext}` |
| 채팅 이미지 | Chat | `chat/{yyyy}/{MM}/{dd}/{uuid}.{ext}` |

공개 URL 예:
```text
https://<cloudfront-domain>/posts/a1b2.../c3d4....jpg
https://<cloudfront-domain>/profiles/42/e5f6....png
https://<cloudfront-domain>/chat/2026/08/25/g7h8....webp
```

---

## 3. 공통 API 패턴

서비스마다 경로 prefix만 다르고 **동작은 동일**.

### 3-1. Presigned 업로드 URL 발급 (등록 준비)

```http
POST /api/v1/{domain}/media/presign
Authorization: Bearer ...
Content-Type: application/json

{
  "contentType": "image/jpeg",
  "contentLength": 1234567,
  "contextId": "optional-post-or-room-or-user-id"
}
```

**BE 처리**
1. 인증 확인  
2. `contentLength` ≤ 5MB, `contentType` 화이트리스트  
3. `s3_key` 생성 (위 prefix 규칙)  
4. S3 Presigned PUT URL 발급 (만료 예: 5분)  
5. 응답

```json
{
  "uploadUrl": "https://s3..../presigned...",
  "s3Key": "posts/.../uuid.jpg",
  "publicUrl": "https://<cloudfront-domain>/posts/.../uuid.jpg",
  "expiresInSeconds": 300,
  "maxBytes": 5242880
}
```

**FE**
1. `uploadUrl`로 `PUT` (Header: `Content-Type` = 발급 때와 동일)  
2. 성공 후 비즈니스 API에 `s3Key` / `publicUrl` 전달 (글 작성, 프로필 수정, 채팅 메시지 등)

### 3-2. 업로드 확정 / DB 연결 (비즈니스 API)

예:
- 글 작성·수정 시 `imageUrls[]` 또는 `imageKeys[]`
- 프로필 수정 시 `profileImageKey`
- 채팅 메시지 전송 시 `type=IMAGE`, `imageKey` / `imageUrl`

BE는 **S3에 파일이 있는지 head(선택)** 후 DB 저장.

### 3-3. 수정

권장:
1. 새 Presigned로 **새 key** 업로드  
2. DB를 새 `publicUrl`/`s3Key`로 갱신  
3. 예전 key `DeleteObject` (실패해도 비즈니스는 새 URL 기준)

### 3-4. 삭제

```http
DELETE /api/v1/{domain}/media
Authorization: Bearer ...
Content-Type: application/json

{ "s3Key": "posts/.../uuid.jpg" }
```

또는 글/메시지/프로필 삭제 API 안에서:
1. DB에서 URL/key 제거  
2. S3 `DeleteObject`  
3. (선택) CloudFront Invalidation — 보통 TTL에 맡기고 생략 가능

---

## 4. 도메인별 메모

### 4-1. 게시글 (Product-Post / listing)

- 이미지 여러 장 가능하면 `posts/{postId}/{uuid}.ext` 여러 key  
- 글 삭제 시 해당 post의 key들 일괄 삭제  
- Gateway 경로 예: `/listing-service/...` 또는 팀 라우팅 규칙에 따름

### 4-2. 프로필 (Member)

- 유저당 최신 1장 권장 → 교체 시 이전 key 삭제  
- `profiles/{userId}/...`

### 4-3. 채팅 (Chat)

- 메시지 본문과 분리: 메타는 Mongo/MySQL, 바이너리는 S3  
- **Key (Chat 구현 기준)**: `chat/{yyyy}/{MM}/{dd}/{uuid}.{ext}`  
  - 예: `chat/2026/08/25/a1b2c3d4-....jpg`  
- 메시지 페이로드에 `imageUrl`(CloudFront) 포함해 클라이언트가 바로 표시  
- 앱은 이미지 바이트를 프록시하지 않음 (조회는 CloudFront GET)  
- 방/메시지 삭제 정책에 맞춰 S3 정리 (비동기 OK)

---

## 5. env (컨테이너에 이미 주입되는 이름)

compose `x-media-env` 기준:

| 변수 | 용도 |
| --- | --- |
| `AWS_REGION` | SDK 리전 |
| `S3_BUCKET` | Presigned·Delete 대상 버킷 |
| `CLOUDFRONT_DOMAIN` | 호스트만 |
| `CLOUDFRONT_BASE_URL` | `publicUrl` 조립 |
| `CLOUDFRONT_DISTRIBUTION_ID` | (선택) Invalidation |

앱 코드 예:
`publicUrl = CLOUDFRONT_BASE_URL + "/" + s3Key`

---

## 6. 에러 코드 권장

| 상황 | HTTP |
| --- | --- |
| 5MB 초과 | 400 |
| 허용하지 않는 contentType | 400 |
| 미인증 | 401 |
| 타인 리소스 key 삭제 시도 | 403 |
| key 없음 | 404 |

---

## 7. 구현 체크리스트 (서비스별)

- [ ] Presigned 발급 API + 5MB / contentType 검증  
- [ ] Presigned에 content-length-range(가능 시)  
- [ ] 비즈니스 API에 `s3Key`/`publicUrl` 저장  
- [ ] 수정 시 새 key + 구 key 삭제  
- [ ] 삭제 시 S3 DeleteObject  
- [ ] Swagger에 미디어 API 문서화  
- [ ] (FE) 5MB 사전 체크 + CloudFront URL로 표시  

대상 서비스: **Product-Post**, **Member(프로필)**, **Chat**

---

## 8. 관련 문서

| 문서 | 내용 |
| --- | --- |
| [media-architecture.md](./media-architecture.md) | S3/CF 아키텍처·업조수삭 흐름 |
| [media-s3-cloudfront.md](./media-s3-cloudfront.md) | 인프라 세팅 로그 |
| `env/apps.env.example` | Apps env 이름 예시 |
