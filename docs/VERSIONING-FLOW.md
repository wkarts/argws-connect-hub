# HUB — fluxo de branches, builds e publicação

## Regra principal

A `develop` é a fonte estável de integração do HUB. Nenhum workflow altera automaticamente `VERSION`, `package.json`, `RELEASE-MANIFEST.json`, `develop`, `main` ou qualquer outro arquivo/branch para criar versão.

Não existe controle automático de `major`, `minor`, `patch`, `auto`, labels `version:*`, cálculo SemVer por título de PR ou commit gerado por pipeline.

Os arquivos `VERSION`, `package.json` e `RELEASE-MANIFEST.json` permanecem somente como metadados compatíveis da fonte. O CI pode validar consistência entre eles, mas nunca os modifica.

## Branches

- `develop`: integração estável e imagem de desenvolvimento.
- `main`: produção. Recebe somente promoção por PR `develop -> main`.
- feature/fix: partem de `develop` e retornam a `develop` por PR.

Nenhuma automação faz `git push` ou cria commit em `develop`/`main`.

## Identidade dos builds da aplicação

A identidade de uma imagem é derivada da branch e do commit Git, não de SemVer automático.

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

## Imagens-base sem versionamento manual

As bases `build`, `runtime` e `deps` são **content-addressed**. Não existe `docker/base/VERSION` e não existe bump manual/automático de base.

`scripts/resolve-hub-base-refs.sh` calcula SHA-256 determinístico das definições relevantes e gera tags no formato:

- `argws-connect-hub-build-base:def-<sha256>`
- `argws-connect-hub-runtime-base:def-<sha256>`
- `argws-connect-hub-deps-base:def-<sha256>`

O alias `latest` de cada base aponta para a definição corrente, mas os builds da aplicação usam sempre a referência content-addressed exata. Assim, uma alteração real de dependências produz naturalmente uma nova tag sem sobrescrever a anterior e sem alterar arquivo de versão.

## Fluxo oficial

`feature/fix -> PR -> develop -> PR develop -> main -> GHCR main/latest/sha`

A publicação de `main` só é autorizada quando o commit veio de PR mesclada `develop -> main` ou de `workflow_dispatch` explicitamente executado sobre `main`.
