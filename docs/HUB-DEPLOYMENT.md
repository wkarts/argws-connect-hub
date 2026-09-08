# HUB — implantação GHCR / AMD64

## Imagens

A aplicação publica em `ghcr.io/<owner>/hub`. Esta distribuição usa somente `linux/amd64`.

Por política de registry, os seguintes containers-base devem existir no GHCR do projeto antes do primeiro build/deploy:

- `ghcr.io/wkarts/hub-ruby:3.3.8-alpine3.19`
- `ghcr.io/wkarts/hub-postgres:16-alpine`
- `ghcr.io/wkarts/hub-redis:7-alpine`
- `ghcr.io/wkarts/hub-mailhog:latest` (somente desenvolvimento)
- `ghcr.io/wkarts/hub-codespace:latest` (desenvolvimento/codespaces)

A imagem da aplicação é `ghcr.io/wkarts/hub:latest` por padrão e pode ser alterada com `HUB_IMAGE`.

## Produção

1. Copie `.env.example` para `.env`.
2. Defina `SECRET_KEY_BASE`, `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `FRONTEND_URL` e as credenciais da Connect|API.
3. Execute as migrations antes/depois da atualização conforme seu fluxo operacional.
4. Suba `docker-compose.production.yaml` no Dockge/Compose.

## Connect|API

```env
CONNECT_API_BASE_URL=https://api.connect.exemplo.com
CONNECT_API_AUTH_TOKEN=token-global-da-connect-api
```

O token global é usado somente pelo backend HUB para provisionar instâncias isoladas. O navegador não recebe esse segredo.


## Desenvolvimento / Codespace

O workflow opcional publica `ghcr.io/wkarts/hub-codespace:latest` em AMD64 e usa `ghcr.io/wkarts/hub:latest` como imagem-pai. Ele não é necessário para produção.
