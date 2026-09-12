# HUB — fluxo de promoção para produção

## Fonte de verdade

A fonte funcional de produção é sempre a revisão existente na `develop` no momento em que a PR `develop -> main` é aberta.

O fluxo de promoção não recalcula versão e não modifica arquivos de código.

## O que foi removido

O HUB não utiliza mais:

- `force_bump`;
- `auto`, `patch`, `minor` ou `major` como estratégia de release;
- labels `version:major`, `version:minor` ou `version:patch`;
- `.github/scripts/compute-next-version.mjs`;
- `.github/scripts/apply-version.mjs`;
- commits automáticos de `VERSION`, `package.json` ou `RELEASE-MANIFEST.json`;
- `git push` de workflow para `main` ou `develop`;
- criação automática de tag/GitHub Release SemVer.

## Develop

Um merge em `develop` pode validar e construir artefatos, mas não altera a árvore Git.

A imagem de desenvolvimento usa identidade `develop-<sha-curto>` e é publicada nos aliases `develop`, `develop-<sha-curto>` e `sha-<sha-completo>`.

## Main

`main` aceita promoção somente a partir de `develop`.

Após o merge da PR `develop -> main`, o workflow `GHCR - Publish Main Image`:

1. confirma que o commit veio de PR mesclada `develop -> main`;
2. valida exatamente o SHA recebido;
3. constrói uma única imagem `linux/amd64`;
4. publica o mesmo digest em `main`, `latest`, `main-<sha-curto>` e `sha-<sha-completo>`;
5. verifica digest, revisão, build identity e canal `stable`.

Nenhum passo modifica `develop` ou `main`.

## Histórico

Tags, GitHub Releases e imagens versionadas já existentes não são apagadas nem reescritas. Elas permanecem como histórico das publicações anteriores.
