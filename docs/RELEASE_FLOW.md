# HUB — promoção idempotente para produção

## Fonte de verdade

A fonte funcional de produção é a revisão existente em `develop` no momento da PR `develop -> main`.

`VERSION`, `package.json` e `RELEASE-MANIFEST.json` continuam declarando o mesmo SemVer, mas esse valor é **metadado da fonte**. Ele não é usado como trava para cada promoção e não precisa ser incrementado apenas porque uma nova revisão de `develop` será promovida para `main`.

O fluxo não faz bump automático, não reescreve a fonte e não cria commits ou tags de versão durante a promoção.

## Desenvolvimento

A publicação de desenvolvimento usa identidade por branch e SHA:

- `ghcr.io/wkarts/argws-connect-hub:develop`;
- `ghcr.io/wkarts/argws-connect-hub:develop-<sha-curto>`;
- `ghcr.io/wkarts/argws-connect-hub:sha-<sha-completo>`.

O alias `develop` é móvel. Os aliases derivados do SHA existem para rastreabilidade e recuperação exata de uma revisão.

## Gate da PR para main

`main` aceita promoção somente a partir de `develop`.

Antes do merge, o gate valida:

1. origem `develop -> main`;
2. sincronismo de `VERSION`, `package.json` e `RELEASE-MANIFEST.json`;
3. formato SemVer válido do metadado de versão;
4. invariantes de build, deployments e bases content-addressed;
5. ausência de mecanismos de bump ou mutação automática de versão.

A existência prévia de `vX.Y.Z` **não bloqueia** uma nova promoção. Isso é intencional: tags SemVer históricas não são a identidade operacional de uma promoção `develop -> main`.

## Publicação de main

Após o merge da PR `develop -> main`, o workflow usa o SHA exato recebido em `main` e publica os aliases:

- `ghcr.io/wkarts/argws-connect-hub:main`;
- `ghcr.io/wkarts/argws-connect-hub:latest`;
- `ghcr.io/wkarts/argws-connect-hub:main-<sha-curto>`;
- `ghcr.io/wkarts/argws-connect-hub:sha-<sha-completo>`.

A identidade gravada dentro da imagem é `main-<sha-curto>`, e a revisão OCI é o SHA completo de `main`.

O workflow não cria `vX.Y.Z` nem GitHub Release automaticamente. Tags SemVer já existentes permanecem intactas e continuam servindo como histórico quando tiverem sido criadas por outro processo deliberado.

## Idempotência

A promoção e a publicação podem ser executadas novamente para o mesmo SHA sem conflito de versionamento.

Na primeira execução de um SHA de `main`:

1. o workflow valida a fonte exata;
2. resolve as bases `def-<sha256>`;
3. constrói a imagem `linux/amd64`;
4. publica `main`, `latest`, `main-<sha-curto>` e `sha-<sha-completo>`;
5. valida digest, revisão, identidade e canal `stable`.

Em uma reexecução do mesmo SHA:

1. o workflow detecta `main-<sha-curto>` já publicado;
2. reaplica `main`, `latest` e os aliases de SHA para o digest existente;
3. não recompila a imagem já publicada;
4. valida novamente todos os aliases e a identidade interna.

Assim, reexecutar o pipeline converge para o mesmo artefato em vez de falhar por tag SemVer já existente.

## O que continua proibido

O HUB não utiliza:

- bump automático `major`, `minor` ou `patch`;
- labels para calcular versão;
- scripts `compute-next-version.mjs` ou `apply-version.mjs`;
- commits automáticos de versão;
- `git push` automático para `main` ou `develop`;
- `docker/base/VERSION`;
- criação automática de tag SemVer durante uma promoção comum `develop -> main`;
- exigência de incrementar `VERSION` apenas para permitir uma nova promoção.

O metadado SemVer permanece sincronizado e auditável, mas a identidade operacional de cada build é determinada pela branch e pelo SHA.
