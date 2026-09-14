# HUB — release automático e promoção para produção

## Fluxo oficial

`feature/fix -> develop -> PR develop -> main -> SemVer automático -> GHCR + tag + GitHub Release`

A promoção para `main` aceita somente `develop`. O workflow calcula a próxima versão a partir da última tag `vX.Y.Z`.

## Modos

- `auto`: padrão; breaking/`version:major` => major, `feat:`/`version:minor` => minor, demais => patch.
- `patch`: força patch.
- `minor`: força minor.
- `major`: força major.

No push normal de `develop -> main`, usa `auto`. No `workflow_dispatch`, o operador escolhe `auto`, `patch`, `minor` ou `major`.

Com `v1.1.3` como release atual, uma PR comum intitulada `Develop` gera `v1.1.4`.

## Pacote GHCR canônico

Existe um único pacote de aplicação:

`ghcr.io/wkarts/argws-connect-hub`

Um release `1.1.4` publica o mesmo digest em:

- `:1.1.4`
- `:1.1`
- `:1`
- `:latest`
- `:main`
- `:main-<sha-curto>`
- `:sha-<sha-completo>`

O workflow rejeita qualquer referência fora desse pacote. `mains` não faz parte do contrato.

## Idempotência

- se o mesmo SHA já tem `vX.Y.Z`, reutiliza essa versão;
- se `argws-connect-hub:X.Y.Z` já existe, não reconstrói; apenas reconcilia aliases;
- tag e GitHub Release existentes no mesmo SHA são mantidos;
- reexecução de SHA antigo não retrocede `latest`, `main`, `X` ou `X.Y`.

## Fonte Git sem conflito

`VERSION`, `package.json` e `RELEASE-MANIFEST.json` continuam sincronizados como metadados da fonte, mas o release não cria commit automático de versão em `main` ou `develop`.

A versão efetiva do artefato é passada ao Docker como `HUB_VERSION`, registrada em `/app/.hub_version`, nas labels OCI, nas tags GHCR e no GitHub Release. Assim o SemVer automático volta sem deixar `main` artificialmente à frente de `develop`.

## Bases

As bases continuam content-addressed por `def-<sha256>` e não participam do SemVer da aplicação.
