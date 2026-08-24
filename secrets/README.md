# Secrets (git ignored except this README)

Do **not** commit real keys / PEM files.

## Media (S3 / CloudFront)

- `media-app.env` — Access Key 등 **실값** (로컬·도구용, git ignore)
- 예시 템플릿: `env/media-app.env.example` (커밋 OK, placeholder만)
- Apps EC2는 Instance Role 사용 권장 (키 불필요)
- 아키텍처: `docs/media-architecture.md`

## JWT RS256 keys for Auth / Gateway (Prod)

On Apps EC2:

```bash
mkdir -p /opt/valuehub-aws-infra/secrets
# copy jwt-private.pem and jwt-public.pem here (from auth-service key generation)
chmod 600 secrets/jwt-private.pem
chmod 644 secrets/jwt-public.pem
```

Required files:

- `jwt-private.pem` — auth-service
- `jwt-public.pem` — auth-service + gateway
