# HUB — fluxo de branches, versões, builds e publicação

## Regra principal

A `develop` é a fonte estável de integração e prepara explicitamente a **próxima versão de release**. A `main` representa o último release de produção.

O HUB usa SemVer explícito nos metadados da fonte:

- `VERSION`;
- `package.json`;
- `RELEASE-MANIFEST.json`.

Os três arquivos devem permanecer sincronizados. Nenhum workflow calcula `major`, `minor` ou `patch`, faz bump automático, reescreve esses arquivos ou cria commit automático de versão.

Exemplo de ciclo:

- produção atual: `main = 1.1.1`;
- próximo release em desenvolvimento: `develop = 1.1.2`;
- após a promoção `develop -> main`, ambas representam `1.1.2`;
- antes do ciclo seguinte, `develop` passa explicitamente para a próxima versão planejada.

## Branches

- `develop`: integração estável e próxima versão de release em preparação;
- `main`: produção e último release publicado;
- feature/fix: partem de `develop` e retornam a `develop` por PR.

A promoção oficial é sempre `develop -> main`.

## Imagem de desenvolvimento

O nome/tag principal da imagem de desenvolvimento **permanece sempre**:

- `ghcr.io/wkarts/argws-connect-hub:develop`.

Tags `develop-<sha-curto>` e `sha-<sha-completo>` podem existir adicionalmente para rastreabilidade durante a build, mas imagens antigas desse canal são removidas pela política de retenção.

O valor SemVer preparado em `VERSION` não transforma a imagem de desenvolvimento em `:X.Y.Z`; a publicação SemVer acontece somente após promoção para `main`.

## Release de produção

Quando uma PR `develop -> main` é mesclada, a `main` recebe exatamente a mesma versão declarada na `develop`. O workflow não modifica arquivos de versão; ele apenas valida e publica.

Para `VERSION=1.1.2`, o mesmo digest de produção é publicado como:

- `ghcr.io/wkarts/argws-connect-hub:1.1.2`;
- `ghcr.io/wkarts/argws-connect-hub:1.1`;
- `ghcr.io/wkarts/argws-connect-hub:1`;
- `ghcr.io/wkarts/argws-connect-hub:latest`.

Uma referência `sha-<sha-completo>` pode ser criada para auditoria durante a publicação.

A publicação também cria:

- tag Git anotada `v1.1.2`;
- GitHub Release `HUB v1.1.2`.

A PR para `main` é bloqueada se a versão declarada não for SemVer válida, não estiver sincronizada ou não for maior que o release já publicado.

## Retenção GHCR

O pacote principal `ghcr.io/wkarts/argws-connect-hub` mantém somente:

1. a imagem do release atual (`X.Y.Z`);
2. a imagem do release imediatamente anterior;
3. a imagem que contém o alias permanente `:develop`.

Aliases do release atual (`X.Y`, `X`, `latest`) permanecem no mesmo digest do release atual. Versões de pacote mais antigas são removidas do GHCR após builds bem-sucedidas.

A remoção de uma imagem antiga do GHCR **não remove** a tag Git histórica nem o GitHub Release histórico.

## Cache de build

Após uma build bem-sucedida, o workflow remove caches do GitHub Actions que não foram acessados nas últimas **2 horas**. Caches usados dentro dessa janela permanecem disponíveis para acelerar builds próximas.

## Imagens-base

As bases `build`, `runtime` e `deps` continuam **content-addressed**. Não existe `docker/base/VERSION`.

`scripts/resolve-hub-base-refs.sh` calcula SHA-256 determinístico das definições relevantes e gera referências no formato:

- `argws-connect-hub-build-base:def-<sha256>`;
- `argws-connect-hub-runtime-base:def-<sha256>`;
- `argws-connect-hub-deps-base:def-<sha256>`.

Versionamento SemVer da aplicação e identidade content-addressed das bases são mecanismos independentes.

## Fluxo oficial

`feature/fix -> PR -> develop -> definir próxima VERSION -> PR develop -> main -> GHCR X.Y.Z/X.Y/X/latest -> tag vX.Y.Z -> GitHub Release`
