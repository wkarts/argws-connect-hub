# HUB — arquitetura de build e publicação

## Objetivo

Manter builds reprodutíveis sem permitir que CI/CD altere branches ou arquivos de versionamento.

## Fonte

`develop` é a linha estável de integração. `main` recebe somente PR `develop -> main`.

## Metadados da aplicação

`VERSION`, `package.json` e `RELEASE-MANIFEST.json` são metadados da fonte. O CI valida sincronismo e não os modifica.

## Imagens-base content-addressed

As bases são publicadas em repositórios separados:

- `argws-connect-hub-build-base`;
- `argws-connect-hub-runtime-base`;
- `argws-connect-hub-deps-base`.

A identidade de cada base é `def-<sha256>`, calculada por `scripts/resolve-hub-base-refs.sh` a partir da definição efetiva. Não existe arquivo de versão de base.

A base de dependências incorpora em seu hash a identidade da base `build`, além de locks e pacotes locais. Assim qualquer alteração material cria uma nova referência naturalmente.

Os aliases `latest` são atualizados pelo workflow de bases, porém builds oficiais de aplicação consomem somente a referência `def-<sha256>` exata.

## Build de develop

`GHCR - Publish Development Image` valida o SHA de `develop`, resolve as bases exatas, compila e publica:

- `develop`;
- `develop-<sha-curto>`;
- `sha-<sha-completo>`.

## Build de main

`GHCR - Publish Main Image` só publica após promoção `develop -> main` (ou despacho manual explicitamente sobre `main`), resolve as bases content-addressed e publica o mesmo digest em:

- `main`;
- `latest`;
- `main-<sha-curto>`;
- `sha-<sha-completo>`.

## Proibições

Os pipelines não fazem bump `major/minor/patch`, não calculam SemVer, não criam commits de versão, não fazem push em branch e não recriam tags históricas.
