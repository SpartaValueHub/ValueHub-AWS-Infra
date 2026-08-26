# Kafka 구조 · 흐름

Outbox / Saga 없음. 각 서비스가 **자기 DB 커밋 후** `KafkaTemplate.send` 한 번.
Kafka는 MySQL/Mongo에 쓰지 않는다. 메시지 버스만 제공한다.

브로커 기동은 [aws-setup.md](./aws-setup.md). 이 문서가 토픽·페이로드 계약의 기준이다.

---

## 1. 어디에 뜨나

브로커는 **Apps EC2 Docker** (`compose.prod-apps.yml`). Redis·MSA와 같은 `valuehub-apps` 네트워크다.

DB EC2가 아니다. 데이터 변경은 Apps의 각 서비스가 자기 MySQL/Mongo에 하고, Kafka는 그 서비스들끼리 이벤트만 전달한다.
같은 compose라 bootstrap이 `kafka:19092` 한 줄이면 되고, DB private IP·SG 9092가 필요 없다.
Infra CD(`deploy-apps.yml`)가 Apps compose를 올리므로 브로커도 그 경로로 뜬다.

```text
Apps EC2 (compose.prod-apps.yml)
  Gateway / MSA / Redis
  Reservations / Product-Post / Member / Chat
         │  kafka:19092 (docker DNS)
         ▼
  valuehub-kafka   reservation.events
                   product.events
                   member.events

DB EC2 (compose.prod-db.yml)
  MySQL :3306
  Mongo :27017
```

| 무엇 | 어디서 |
| --- | --- |
| 예약·상품·회원·채팅 **데이터** | DB EC2 (MySQL / Mongo) |
| Kafka **브로커** | Apps EC2 `valuehub-kafka` |
| produce / consume **앱** | Apps EC2 (같은 네트워크) |

서비스는 compose가 `SPRING_KAFKA_BOOTSTRAP_SERVERS=kafka:19092` 를 넣는다. `.env`에 Kafka 호스트를 안 적어도 된다.

Kafka UI는 Apps 로컬 `127.0.0.1:8080`. SG에 8080·9092를 열지 않음. SSH 터널:

`ssh -i .valuehub-aws-prod.pem -L 8080:127.0.0.1:8080 ubuntu@54.116.150.139`

Prod는 KRaft **1대**. ZooKeeper 없음. 이미지 `apache/kafka:4.3.1`.

---

## 2. 토픽

기동 시 `kafka-init`이 `--if-not-exists`로 만든다. 파티션 3, replication 1.
필드마다 토픽을 쪼개지 않는다.

| 토픽 | 파티션 키 | Producer | Consumer |
| --- | --- | --- | --- |
| `reservation.events` | `productPostUuid` | Reservations | Chat, Product-Post (`listing`) |
| `product.events` | `productPostUuid` | Product-Post (`listing`) | Chat |
| `member.events` | `memberUuid` | Member | Chat |

지역공유(LOCATION): Kafka 없음. Chat 웹소켓만.
게시글 **등록** CREATE 이벤트 없음. 방 생성 때 Chat이 Product/Member API로 INSERT.

group-id (오프셋 독립):

| 서비스 | group-id |
| --- | --- |
| Chat | `chat-service` |
| Product-Post | `listing-service` |

### 발행 규칙

- 같은 DB 트랜잭션에 Kafka send를 넣지 않는다. **커밋 성공 후** send.
- 값 직렬화: JSON. `spring.json.add.type.headers: false` (클래스 FQCN 헤더 없음).
- 한 액션 = 이벤트 1건. PATCH 컬럼마다 발행하지 않음.
- 컨슈머는 비동기. API 응답은 자기 DB 커밋까지.

---

## 3. 예약 흐름 (`reservation.events`)

원본은 Reservations. 말풍선·헤더 스냅샷은 Chat. 상품 거래상태는 Product-Post.

클라이언트가 Chat으로 `RESERVATION` 타입을 보내면 안 된다. 일반 전송 API는 거절.
말풍선은 Chat 컨슈머가 insert.

```text
판매자 → Reservations API
           │
           ├─ Reservations DB commit
           └─ (커밋 후) reservation.events 1건
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
      Chat                    Product-Post
      말풍선 insert            productPostUuid만 보고
      CREATED → 헤더 예약중    CREATED → RESERVED
      UPDATED → 말풍선만       UPDATED → 무시
      CANCELED → 헤더 판매중   CANCELED → SELLING
```

| eventType | Chat | Product-Post |
| --- | --- | --- |
| `CREATED` | 말풍선 + 헤더 예약중 | `productPostUuid` → 상품 **RESERVED** |
| `UPDATED` | 말풍선만 | 무시 |
| `CANCELED` | 말풍선 + 헤더 판매중 | `productPostUuid` → 상품 **SELLING** |

Product는 예약 스냅샷·`RESERVED`/`SELLING` 문자열을 받지 않는다.
`eventType` + `productPostUuid`만 보고 스스로 상태를 바꾼다.

수정은 거래상태 변경 없음 (약속 정보만). PATCH 한 번 = 이벤트 1건.

키: `productPostUuid` (같은 상품의 등록→취소 순서 보장)

```json
{
  "eventType": "CREATED",
  "productPostUuid": "...",
  "reservationUuid": "...",
  "chatRoomUuid": "...",
  "meetAt": "2026-08-26T12:00:00+09:00",
  "placeName": "...",
  "sellerUuid": "...",
  "buyerUuid": "...",
  "updatedAt": "2026-08-26T01:00:00Z"
}
```

- Chat: 스냅샷으로 말풍선 구성. 헤더 거래상태는 `CREATED` → 예약중, `CANCELED` → 판매중.
- Product: `eventType`, `productPostUuid`만 사용. 나머지 필드는 무시.
- `meetAt` / `placeName` 등 말풍선 필드는 Reservations 엔티티에 맞게 맞출 것. 컬럼마다 이벤트를 나누지 말고 **처리 후 스냅샷 전체**를 한 번에 보낸다.

---

## 4. 상품 → Chat (`product.events`)

방 생성 때 Chat이 Product API로 `chat_product_posts` INSERT.
이후 글 수정 · 거래상태 · 삭제는 **스냅샷 1종류**로 덮어쓴다.
삭제돼도 채팅방은 유지. `productPostStatus = DELETED`면 뷰에 삭제됨 표시.

```text
Product-Post DB commit
    → product.events (현재 값 전체)
    → Chat: product_post_uuid 로 UPDATE
```

키: `productPostUuid`

```json
{
  "productPostUuid": "...",
  "productPostName": "버버리 레더 포켓 미니 토트백",
  "price": 1500000,
  "thumbnailUrl": "https://...",
  "tradeStatus": "RESERVED",
  "productPostStatus": "PUBLIC",
  "updatedAt": "2026-08-26T01:00:00Z"
}
```

| Producer | `chat_product_posts` |
| --- | --- |
| `productPostUuid` | `product_post_uuid` |
| `price` | `price` |
| `thumbnailUrl` | `product_post_image_url` |
| `productPostName` | `product_post_name` |
| `tradeStatus` | `trade_status` |
| `productPostStatus` | `product_post_status` |
| `updatedAt` | `updated_at` |

`tradeStatus`: `SELLING` / `RESERVED` / `SOLD_OUT`  
`productPostStatus`: `PUBLIC` / `DELETED` (HIDDEN은 이번 범위에서 안 보냄)  
삭제 시 같은 이벤트에 `"productPostStatus": "DELETED"`.

안 보내는 것: 게시글 등록, HIDDEN, 이미지 전체(대표 1장만), 거래 희망 동/구/장소.

---

## 5. 회원 → Chat (`member.events`)

마이페이지 프로필 사진 변경만. 닉네임은 안 보냄 (방 생성 스냅샷 유지).
이후 닉네임 변경은 기존 방에 반영하지 않음.

```text
Member DB commit
    → member.events
    → Chat: member_uuid 로 profile_image_url, updated_at UPDATE
```

키: `memberUuid`

```json
{
  "memberUuid": "...",
  "profileImageUrl": "https://...",
  "updatedAt": "2026-08-26T01:00:00Z"
}
```

---

## 6. 방 생성 vs 이후 (전체)

```text
[방 생성] Kafka 없음
  Chat → Product 조회  → chat_product_posts INSERT
  Chat → Member 조회   → 회원 테이블 INSERT (닉네임, 프사)

[이후]
  예약 등록/수정/취소
    Reservations commit → reservation.events
      Chat: 말풍선 (+ CREATED/CANCELED 이면 헤더)
      Product: CREATED=RESERVED, CANCELED=SELLING, UPDATED=무시

  상품 글 수정 / 거래상태 / 삭제
    Product commit → product.events
      Chat: chat_product_posts UPDATE
      DELETED 이면 뷰에 삭제됨 (방 유지)

  회원 프사 변경
    Member commit → member.events
      Chat: profile_image_url UPDATE
```

API 트랜잭션은 자기 DB 커밋까지. Chat·Product 반영은 그다음 비동기.

---

## 7. 인프라에서 주입하는 것

인프라는 bootstrap을 compose에 **고정**한다 (`kafka:19092`). serializer / group-id / DTO는 각 서비스 레포.

주입 대상: `member`, `listing`, `reservations`, `chat`. 토픽 생성은 `kafka-init` (`--if-not-exists`).

복사 템플릿: [`kafka/spring/`](../kafka/spring/).

SG: Kafka 포트는 호스트 로컬만 (`127.0.0.1:9092`, UI `127.0.0.1:8080`). 인터넷에 열지 않음.
