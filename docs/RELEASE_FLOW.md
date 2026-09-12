# HUB Release Flow

## Regra principal

`main` recebe alterações exclusivamente por Pull Request originada de `develop`.

Não fazer push direto, force-update, merge local ou sincronização manual de conteúdo para `main`.

## Fluxo de desenvolvimento

1. Criar branch de feature/fix a partir de `develop`.
2. Implementar, testar e abrir PR para `develop`.
3. Mesclar a PR somente depois do CI aprovado.
4. Repetir para as próximas implementações.

## Preparação de release

Antes de abrir a PR `develop -> main`, a versão deve estar definida em `develop` e sincronizada nos três arquivos:

- `VERSION`
- `package.json`
- `RELEASE-MANIFEST.json`

Use SemVer `X.Y.Z`. O script `scripts/validate-version-sync.sh` valida a consistência.

A versão de release deve ser maior que a última tag `vX.Y.Z` publicada.

## PR de release

A PR de publicação deve usar:

- head: `develop`
- base: `main`

O workflow `Main Release PR Policy` rejeita PR para `main` criada a partir de qualquer outra branch e valida o versionamento antes do merge.

Depois do merge de uma PR normal `develop -> main`, o workflow de release:

1. valida o código e os deployments;
2. lê a versão já declarada no código;
3. valida que a tag ainda não existe;
4. constrói e publica a imagem imutável;
5. publica as tags de imagem da versão;
6. cria a tag Git anotada;
7. cria a GitHub Release.

O workflow não altera `VERSION`, `package.json` ou `RELEASE-MANIFEST.json` e não cria commit automático de versionamento na `main`.

## Sincronização sem release

Excepcionalmente, uma PR `develop -> main` pode ser usada apenas para normalização de fluxo/metadados sem gerar release nova. Nesse caso, o título deve conter:

`[skip release]`

Mesmo nesse modo, a PR continua obrigada a vir de `develop` e os três arquivos de versão precisam estar sincronizados.

## Resultado esperado

O histórico fica previsível:

`feature/fix -> develop -> main -> tag/release`

A versão é preparada antes da promoção e a `main` nunca passa a ser fonte de mudanças de produto que precisem voltar para `develop`.
