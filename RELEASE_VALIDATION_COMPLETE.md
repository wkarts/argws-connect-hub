# HUB — validação do pacote completo para develop

Data: 2026-09-08
Produto: 🅷🆄🅱 / HUB
Versão base do produto: 1.0.0
Canal: develop
Arquitetura de imagem: linux/amd64
Ruby alvo: 3.3.10

## Gates executados

- `scripts/audit-hub.sh`: **OK**
- Sintaxe Ruby em `app`, `config`, `lib` e `db/migrate`: **675 arquivos OK**
- `package.json`: JSON válido
- `public/manifest.json`: JSON válido
- `RELEASE-MANIFEST.json`: JSON válido
- Workflows `.github/workflows/*.yml`: YAML válido
- fragmentos `.b64` / `.hub/privacy-clean`: **ausentes**
- telemetria/analytics/APM de terceiros: **não encontrada pelo gate de privacidade**
- `AnalyticsHelper`, `$track`, `useTrack` e imports relacionados: **removidos**
- branding HUB/PWA/favicon: **presente**
- Connect|API: integração presente
- e-mail IMAP/SMTP: presente
- IMAP `BODY.PEEK[]`: preservado
- IMAP Sent observer/service: presentes e com sintaxe válida

## CI

- Docker Actions de Buildx/Build-Push atualizadas para linha Node 24 (`setup-buildx-action@v4.3.0`, `build-push-action@v7.3.0`).
- build de PR usa `load: true`, evitando o warning `No output specified with docker-container driver`.
- `assets:precompile` permanece obrigatório; não foi bypassado.
- protobuf fixado em `3.25.8` e o Docker atualiza o lock dessa gem durante o builder.

## Observação

Este arquivo registra validações estáticas executadas no ambiente de entrega. O build Docker integral deve continuar como gate obrigatório do GitHub Actions antes de promoção para `main`.
