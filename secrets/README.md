# JWT RS256 keys for Auth / Gateway (Prod)

Do **not** commit real PEM files.

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
