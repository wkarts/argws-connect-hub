# HUB — implantação GHCR / AMD64

## Imagens

A aplicação é publicada em:

```text
ghcr.io/wkarts/argws-connect-hub
```

Esta distribuição suporta somente `linux/amd64`.

### Canais

Desenvolvimento:

```text
ghcr.io/wkarts/argws-connect-hub:develop
```

Produção estável:

```text
ghcr.io/wkarts/argws-connect-hub:latest
```

Produção imutável:

```text
ghcr.io/wkarts/argws-connect-hub:X.Y.Z
```

O build da aplicação usa diretamente `ghcr.io/linuxcontainers/alpine:3.20` como base e instala Ruby 3.3.x no próprio build. Não existe dependência de uma imagem privada `hub-ruby`.

Os serviços de produção esperam no GHCR:

- `ghcr.io/wkarts/hub-postgres:16-alpine`
- `ghcr.io/wkarts/hub-redis:7-alpine`

Imagens auxiliares de desenvolvimento, como MailHog/Codespace, são opcionais e não fazem parte do runtime de produção.

## Produção

1. Copie `.env.example` para `.env`.
2. Defina `SECRET_KEY_BASE`, `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `FRONTEND_URL` e as credenciais da Connect|API.
3. Use `HUB_IMAGE=ghcr.io/wkarts/argws-connect-hub:latest` ou fixe uma versão `X.Y.Z`.
4. Execute as migrations conforme seu fluxo operacional de atualização.
5. Suba `docker-compose.production.yaml` no Dockge/Compose/CloudPanel.

## Desenvolvimento

Para acompanhar automaticamente a branch `develop`:

```env
HUB_IMAGE=ghcr.io/wkarts/argws-connect-hub:develop
```

A imagem `:develop` nunca promove ou sobrescreve `:latest`.

## Connect|API

```env
CONNECT_API_BASE_URL=https://api.connect.exemplo.com
CONNECT_API_AUTH_TOKEN=token-global-da-connect-api
```

O token global é usado somente pelo backend HUB para provisionar e administrar as instâncias da Connect|API. O navegador não recebe esse segredo.

## Fluxo de release

Consulte `docs/VERSIONING-FLOW.md`.

Resumo:

```text
feature/fix -> develop -> PR develop/main -> main -> SemVer -> GHCR -> vX.Y.Z -> GitHub Release
```
