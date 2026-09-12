# HUB — promoção para produção

## Fonte de verdade

A fonte funcional de produção é a revisão existente em `develop` no momento em que uma PR `develop -> main` é aberta.

O fluxo de promoção não recalcula versão e não modifica arquivos de código.

## Removido definitivamente

O HUB não utiliza mais:

- `force_bump`;
- `auto`, `patch`, `minor` ou `major` como estratégia de release;
- labels `version:major`, `version:minor` ou `version:patch`;
- `.github/scripts/compute-next-version.mjs`;
- `.github/scripts/apply-version.mjs`;
- `docker/base/VERSION`;
- commits automáticos de `VERSION`, `package.json` ou `RELEASE-MANIFEST.json`;
- `git push` de workflow para `main` ou `develop`;
- criação automática de tag/GitHub Release SemVer.

## Bases

As imagens-base são identificadas pelo hash SHA-256 de suas próprias definições. Quando uma entrada muda, surge uma nova referência `def-<sha256>` automaticamente, sem bump, sem reescrita e sem conflito com a base anterior.

## Develop

Um merge em `develop` pode validar e construir artefatos, mas nunca altera a árvore Git.

O publisher de desenvolvimento gera `develop`, `develop-<sha-curto>` e `sha-<sha-completo>`.

## Main

`main` aceita promoção somente a partir de `develop`.

Após o merge da PR `develop -> main`, `GHCR - Publish Main Image`:

1. confirma que o commit veio de PR mesclada `develop -> main`;
2. valida exatamente o SHA recebido;
3. resolve as bases content-addressed exatas;
4. constrói uma única imagem `linux/amd64`;
5. publica o mesmo digest em `main`, `latest`, `main-<sha-curto>` e `sha-<sha-completo>`;
6. verifica digest, revisão, identidade de build e canal `stable`.

Nenhuma etapa altera `develop` ou `main`.
