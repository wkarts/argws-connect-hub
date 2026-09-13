# Dependências externas e bases do HUB

## Regra

As dependências do HUB são materializadas em imagens-base content-addressed. Não existe número de versão manual para essas bases.

A identidade é calculada por `scripts/resolve-hub-base-refs.sh` a partir dos arquivos que realmente determinam o conteúdo:

- Dockerfiles de `build`, `runtime` e `deps`;
- `Gemfile` e `Gemfile.lock`;
- campos de dependência de `package.json`;
- `yarn.lock`;
- pacotes locais em `packages/`;
- identidade exata da base `build` usada pela base de dependências.

Uma mudança produz outra tag `def-<sha256>`. Tags content-addressed nunca são sobrescritas com definição diferente.

Os aliases `latest` existem somente para conveniência operacional/local. Os publishers de `develop` e `main` usam referências content-addressed exatas.

## Aplicação

`docker/Dockerfile` aceita `HUB_DEPS_BASE_IMAGE` e `HUB_RUNTIME_BASE_IMAGE`. Em CI esses argumentos recebem referências imutáveis calculadas do conteúdo; os defaults `:latest` servem apenas para uso local/conveniência.
