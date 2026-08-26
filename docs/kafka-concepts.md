# Kafka 기본 (브로커 / 토픽 / 프로듀서 / 컨슈머)

ValueHub에서 쓰는 네 가지 용어만 정리한다. 이벤트 계약은 [kafka.md](./kafka.md).

한 줄: **프로듀서가 토픽에 메시지를 넣고, 컨슈머가 그 토픽을 읽는다. 둘을 이어 주는 서버가 브로커다.**

```text
Reservations / Product-Post / Member     Chat / Product-Post
        (프로듀서)                              (컨슈머)
            │                                      ▲
            │  send                                │  listen
            ▼                                      │
        ┌──────────────────────────────────────────┘
        │  브로커  valuehub-kafka  (Apps EC2)
        │    토픽  reservation.events
        │    토픽  product.events
        │    토픽  member.events
        └──────────────────────────────────────────
```

Kafka는 DB가 아니다. MySQL/Mongo에 직접 쓰지 않는다. 서비스끼리 “이런 일이 났다”는 이벤트만 전달한다.

---

## 브로커 (Broker)

Kafka **서버**다. 메시지를 받아서 디스크에 쌓고, 컨슈머가 읽어 가게 한다.

| | ValueHub |
| --- | --- |
| 컨테이너 | `valuehub-kafka` |
| 위치 | Apps EC2, `compose.prod-apps.yml` |
| 접속 | 같은 compose 네트워크 `kafka:19092` |

앱은 브로커 주소만 알면 된다. compose가 `SPRING_KAFKA_BOOTSTRAP_SERVERS=kafka:19092` 로 넣는다.

Prod는 브로커 **1대** (KRaft). ZooKeeper 없음.

---

## 토픽 (Topic)

메시지 **분류함**이다. 이름 하나로 “이 종류의 이벤트는 여기”라고 정한다.

필드마다 토픽을 쪼개지 않는다. 종류가 같으면 토픽 1개, 내용으로 구분한다.

| 토픽 | 무엇을 담나 |
| --- | --- |
| `reservation.events` | 예약 등록 / 수정 / 취소 (`CREATED` / `UPDATED` / `CANCELED`) |
| `product.events` | 상품 글 스냅샷 (수정·거래상태·삭제) |
| `member.events` | 회원 프로필 사진 변경 |

기동 때 `kafka-init`이 만든다.

**파티션 키:** 같은 키는 같은 줄에 들어가서 **순서가 유지**된다.  
예약·상품은 `productPostUuid`, 회원은 `memberUuid`. 그래서 같은 상품의 등록→취소가 뒤바뀌지 않는다.

---

## 프로듀서 (Producer)

토픽에 메시지를 **보내는** 쪽. 보통 API가 DB에 저장한 **다음** 보낸다.

| 서비스 | 보내는 토픽 | 언제 |
| --- | --- | --- |
| Reservations | `reservation.events` | 예약 커밋 후 |
| Product-Post | `product.events` | 글 수정 / 거래상태 / 삭제 커밋 후 |
| Member | `member.events` | 프사 변경 커밋 후 |

코드에서는 `KafkaTemplate.send(토픽, 키, JSON)`.

게시글 **등록**은 프로듀서 없음. 방 만들 때 Chat이 Product API로 직접 INSERT.

---

## 컨슈머 (Consumer)

토픽을 **구독해서 읽는** 쪽. 이벤트가 오면 자기 DB를 갱신한다. API 응답과 별개, **비동기**.

| 서비스 | 읽는 토픽 | 하는 일 |
| --- | --- | --- |
| Chat | 세 토픽 전부 | 말풍선, 헤더, `chat_product_posts`, 프사 |
| Product-Post | `reservation.events` | `CREATED` → RESERVED, `CANCELED` → SELLING. `UPDATED`는 무시 |

코드에서는 `@KafkaListener(topics = "...")`.

**group-id:** 컨슈머 팀 이름. 팀이 다르면 같은 메시지를 **각자** 받는다.

| group-id | 서비스 |
| --- | --- |
| `chat-service` | Chat |
| `listing-service` | Product-Post |

Chat과 Product-Post가 `reservation.events`를 둘 다 받는 이유다. group-id를 같게 하면 한 쪽만 받는다.

---

## 한 건이 흐르는 예 (예약 등록)

```text
1. 판매자가 예약 API 호출
2. Reservations가 자기 DB에 저장 (커밋)
3. 프로듀서: reservation.events 에 JSON 1건 (키 = productPostUuid)
4. 브로커가 토픽에 보관
5. 컨슈머 Chat: 말풍선 insert, 헤더 예약중
6. 컨슈머 Product-Post: productPostUuid 보고 상품 RESERVED
```

1~2가 API 응답 범위. 5~6은 그다음.

---

## 이 네 개만 구분하면 되는 이유

| 헷갈리는 말 | 실제 |
| --- | --- |
| Kafka에 예약이 저장된다 | 아니요. 예약 원본은 Reservations DB |
| 브로커가 Chat DB를 고친다 | 아니요. Chat **컨슈머**가 고친다 |
| 토픽 = 테이블 | 아니요. 로그(이벤트 줄)다. 조회 DB가 아님 |

서비스 붙일 yaml: [`kafka/spring/`](../kafka/spring/).
