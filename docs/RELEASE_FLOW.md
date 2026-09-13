# HUB — promoção versionada para produção

## Fonte de verdade

A fonte funcional de produção é a revisão existente em `develop` no momento da PR `develop -> main`.

A versão de release também é definida na `develop` antes da promoção. `VERSION`, `package.json` e `RELEASE-MANIFEST.json` devem declarar o mesmo SemVer.

O workflow de `main` não faz bump, não reescreve a fonte e não cria commit de versão.

## Desenvolvimento

A imagem de desenvolvimento mantém como alias principal permanente:

- `ghcr.io/wkarts/argws-connect-hub:develop`.

Os aliases `develop-<sha-curto>` e `sha-<sha-completo>` são apenas referências adicionais de rastreabilidade.

Uma `develop` com `VERSION=1.1.2` continua publicando a imagem de desenvolvimento como `:develop`; `1.1.2` representa o próximo release preparado, não um release já publicado.

## Gate da PR para main

`main` aceita promoção somente a partir de `develop`.

Antes do merge, o gate valida:

1. origem `develop -> main`;
2. sincronismo de `VERSION`, `package.json` e `RELEASE-MANIFEST.json`;
3. SemVer `X.Y.Z` válida;
4. inexistência de `vX.Y.Z`;
5. versão maior que o último release publicado;
6. invariantes de build, deployments e bases content-addressed.

## Publicação de main

Após o merge da PR `develop -> main`, o workflow:

1. valida exatamente o SHA recebido;
2. lê a versão já declarada na fonte;
3. resolve as bases `def-<sha256>` exatas;
4. constrói uma única imagem `linux/amd64`;
5. publica o mesmo digest em `X.Y.Z`, `X.Y`, `X` e `latest`;
6. pode publicar `sha-<sha-completo>` adicionalmente para auditoria;
7. valida digest, revisão, versão e canal `stable`;
8. cria a tag anotada `vX.Y.Z`;
9. cria o GitHub Release correspondente.

Exemplo para `1.1.2`:

- `:1.1.2`;
- `:1.1`;
- `:1`;
- `:latest`;
- tag `v1.1.2`;
- GitHub Release `HUB v1.1.2`.

## O que continua proibido

O HUB não utiliza:

- bump automático `major`, `minor` ou `patch`;
- labels para calcular versão;
- scripts `compute-next-version.mjs` ou `apply-version.mjs`;
- commits automáticos de versão;
- `git push` automático para `main` ou `develop`;
- `docker/base/VERSION`.

A única escrita Git do release é a criação da tag versionada após a imagem ter sido validada.
