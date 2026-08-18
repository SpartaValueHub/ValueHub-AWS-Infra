#!/bin/bash
echo "=== AUTH STATUS ==="
docker inspect valuehub-auth --format 'status={{.State.Status}} restarts={{.RestartCount}} started={{.State.StartedAt}} error={{.State.Error}}'
echo "=== AUTH LAST LOG ==="
docker logs --tail 80 valuehub-auth 2>&1 | tail -80
echo "=== CURLS ==="
curl -sS -m 5 -o /dev/null -w "auth-docs %{http_code}\n" http://127.0.0.1:8000/auth-service/v3/api-docs
curl -sS -m 5 -o /dev/null -w "chat-docs %{http_code}\n" http://127.0.0.1:8000/chat-service/v3/api-docs
curl -sS -m 5 -o /dev/null -w "member-docs %{http_code}\n" http://127.0.0.1:8000/member-service/v3/api-docs
curl -sS -m 5 -o /dev/null -w "category-docs %{http_code}\n" http://127.0.0.1:8000/category-service/v3/api-docs