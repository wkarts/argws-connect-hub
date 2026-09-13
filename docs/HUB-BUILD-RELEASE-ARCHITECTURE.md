# HUB — arquitetura de build e publicação

## Objetivo

Manter builds reprodutíveis, versionamento SemVer explícito da aplicação e bases imutáveis, sem permitir que CI/CD altere branches ou arquivos de versão.

## Fonte

`develop` é a linha estável de integração e prepara a próxima versão. `main` recebe somente PR `develop -> main` e representa o release de produção.

## Metadados da aplicação

`VERSION`, `package.json` e `RELEASE-MANIFEST.json` são a fonte canônica de SemVer da aplicação e devem permanecer sincronizados.

A versão é definida na `develop` antes da PR de release. O CI valida; nunca calcula bump e nunca modifica esses arquivos.

## Imagens-base content-addressed

As bases são publicadas em repositórios separados:

- `argws-connect-hub-build-base`;
- `argws-connect-hub-runtime-base`;
- `argws-connect-hub-deps-base`.

A identidade de cada base é `def-<sha256>`, calculada por `scripts/resolve-hub-base-refs.sh` a partir da definição efetiva. Não existe arquivo de versão de base.

A base de dependências incorpora em seu hash a identidade da base `build`, além de locks e pacotes locais. Assim qualquer alteração material cria uma nova referência naturalmente.

Os aliases `latest` das bases podem ser atualizados pelo workflow de bases, porém builds oficiais da aplicação consomem a referência `def-<sha256>` exata.

## Build de develop

`GHCR - Publish Development Image` valida o SHA de `develop`, resolve as bases exatas, compila e mantém como alias principal:

- `develop`.

Para rastreabilidade também pode publicar:

- `develop-<sha-curto>`;
- `sha-<sha-completo>`.

Mesmo quando `develop` declara a próxima versão, por exemplo `1.1.2`, a imagem de desenvolvimento continua `:develop`.

## Release de main

A publicação de `main` só ocorre após promoção `develop -> main` (ou despacho manual explicitamente sobre `main`). A versão já declarada na fonte é validada e usada sem qualquer mutação.

Para uma versão `X.Y.Z`, o mesmo digest é publicado em:

- `X.Y.Z`;
- `X.Y`;
- `X`;
- `latest`;
- `sha-<sha-completo>` para auditoria.

Em seguida são criados a tag Git `vX.Y.Z` e o GitHub Release correspondente.

## Proibições

Os pipelines não fazem bump `major/minor/patch`, não calculam a próxima SemVer, não criam commits de versão e não fazem push para `develop` ou `main`.

A criação da tag `vX.Y.Z` é parte explícita do release e ocorre somente depois da validação da imagem versionada.
