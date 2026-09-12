# HUB — fluxo de branches, builds e publicação

## Regra principal

A `develop` é a fonte estável de integração do HUB. Nenhum workflow pode alterar automaticamente `VERSION`, `package.json`, `RELEASE-MANIFEST.json` ou criar commits de versionamento.

Não existe mais controle automático de `major`, `minor`, `patch`, `auto`, labels `version:*` ou cálculo SemVer por título de PR.

Os arquivos `VERSION`, `package.json` e `RELEASE-MANIFEST.json` permanecem no código apenas como metadados compatíveis da fonte. O CI valida que eles não divergiram entre si, mas **nunca os modifica**.

## Branches

- `develop`: integração estável e imagem de desenvolvimento.
- `main`: produção. Recebe somente promoção por PR `develop -> main`.
- Features e correções: partem de `develop` e retornam a `develop` por PR.

Nenhuma automação faz push ou commit em `develop` ou `main`.

## Identidade dos builds

A identidade de uma imagem é derivada da branch e do commit Git, não de bump SemVer automático.

### Develop

- `ghcr.io/wkarts/argws-connect-hub:develop`
- `ghcr.io/wkarts/argws-connect-hub:develop-<sha-curto>`
- `ghcr.io/wkarts/argws-connect-hub:sha-<sha-completo>`

`HUB_BUILD_VERSION=develop-<sha-curto>`.

### Main

Após merge de uma PR `develop -> main`:

- `ghcr.io/wkarts/argws-connect-hub:main`
- `ghcr.io/wkarts/argws-connect-hub:latest`
- `ghcr.io/wkarts/argws-connect-hub:main-<sha-curto>`
- `ghcr.io/wkarts/argws-connect-hub:sha-<sha-completo>`

`HUB_BUILD_VERSION=main-<sha-curto>`.

Tags e GitHub Releases SemVer históricas permanecem preservadas, mas o pipeline não cria novas versões SemVer automaticamente.

## Promoção

Fluxo oficial:

`feature/fix -> PR -> develop -> PR develop -> main -> GHCR main/latest/sha`

A publicação de `main` é autorizada somente para commits oriundos de PR mesclada `develop -> main` ou execução manual explicitamente feita sobre `main`.

## Bases de container

`docker/base/VERSION` continua tendo ciclo próprio e manual para imagens-base imutáveis. Isso não altera o versionamento da aplicação e não cria commits automáticos.

## Privacidade

`scripts/audit-hub.sh` continua sendo gate obrigatório e bloqueia reintrodução de telemetria/analytics/APM de terceiros no runtime distribuído.
