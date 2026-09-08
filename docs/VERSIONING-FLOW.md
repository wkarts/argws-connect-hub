# HUB — fluxo de desenvolvimento e versionamento

## Branches

- `develop`: integração contínua e imagem `ghcr.io/wkarts/argws-connect-hub:develop`.
- `main`: linha estável. Recebe somente promoção por PR `develop -> main`.

Features e correções devem partir de `develop` e retornar para `develop` por PR. A promoção para produção é feita por PR de `develop` para `main`.

## SemVer

O HUB tem linha própria iniciada em `1.0.0`.

- `version:major` ou breaking change: major.
- `version:minor` ou `feat:`: minor.
- `version:patch` ou demais merges: patch.

A release sincroniza `VERSION`, `package.json` e `RELEASE-MANIFEST.json`.

## Imagens

### Develop

- `ghcr.io/wkarts/argws-connect-hub:develop`
- `ghcr.io/wkarts/argws-connect-hub:sha-<commit>`

### Stable

- `:<X.Y.Z>`
- `:<X.Y>`
- `:<X>`
- `:latest`
- `:sha-<commit>`

Todas as imagens publicadas pelo projeto são `linux/amd64`.

## Privacidade

`scripts/audit-hub.sh` é gate obrigatório e bloqueia reintrodução de telemetria/analytics/APM de terceiros no runtime distribuído.
