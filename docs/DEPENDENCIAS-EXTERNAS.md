# Política de dependências do HUB

## Regras

1. O `Gemfile` não instala gems diretamente de repositórios Git.
2. O `package.json` não mascara pacotes de fornecedor com aliases `npm:`.
3. Funcionalidades específicas do HUB ficam no próprio código ou em pacotes `@hub/*` mantidos neste repositório.
4. Dependências genéricas e oficiais do ecossistema podem vir de RubyGems/npm/yarn normalmente.
5. A camada `argws-connect-hub-deps-base` concentra `bundle install` e `yarn install`; builds comuns da aplicação não repetem essas instalações.
6. Uma alteração que mude o conteúdo imutável de uma base exige incremento de `docker/base/VERSION` quando a tag correspondente já existir no GHCR.
7. O código operacional do HUB usa somente namespace próprio `hub_`, `hub-`, `HUB_` e `@hub/*` para identificadores internos do produto.

## Pacotes próprios atuais

- `@hub/utils`: utilidades de interface, variáveis, SLA e typing indicator.
- `@hub/editor`: schema, Markdown, menu e suggestions do editor ProseMirror do HUB.
- `@hub/command-palette`: web component da paleta de comandos do HUB.

Esses pacotes são dependências locais (`file:packages/...`) e fazem parte da mesma árvore-fonte do HUB. Eles não são aliases para pacotes externos.

## Storage

A distribuição atual oferece Disk, S3, Google Cloud Storage e S3-compatible/MinIO. O adapter Azure Storage legado foi retirado porque dependia de uma implementação Git específica de terceiro. Integrações Microsoft OAuth para e-mail permanecem independentes dessa remoção.

## Base de dependências

A imagem:

```text
ghcr.io/wkarts/argws-connect-hub-deps-base:<base-version>
```

é construída a partir de:

- `Gemfile` e `Gemfile.lock`;
- campos de dependências do `package.json`;
- `yarn.lock`;
- `packages/**`;
- `docker/base/deps/Dockerfile`;
- `docker/base/VERSION`.

Ela contém o conjunto completo de gems e módulos JavaScript necessário para build e development. A imagem final de produção remove grupos Ruby de development/test e `node_modules` após a compilação dos assets.

## Gate de CI

`scripts/validate-hub-ci.sh` rejeita:

- referências operacionais ao namespace histórico do fornecedor;
- prefixos históricos de runtime que não pertençam ao namespace HUB;
- gems instaladas diretamente de Git/GitHub;
- ausência dos pacotes locais obrigatórios;
- Dockerfile apontando para versão de base diferente de `docker/base/VERSION`.

Avisos jurídicos de código histórico, quando aplicáveis, são tratados separadamente da cadeia operacional de dependências.
