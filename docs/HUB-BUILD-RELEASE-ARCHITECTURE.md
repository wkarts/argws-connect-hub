# HUB — Build, Release e Deployment

## Escopo

Este documento descreve exclusivamente o ciclo de build/release do HUB.

A Connect|API é outra plataforma, possui build, imagens e versionamento próprios. Nos deployments `embedded-connect-api`, ela apenas compartilha a stack/rede Docker com o HUB. Banco, Redis, volumes e imagens continuam separados.

## Serviços pertencentes ao HUB

### Produção

| Função | Service / container |
| --- | --- |
| Rails/Web | `rails-connec-hub` |
| Sidekiq | `sidekiq-connec-hub` |
| Migração/prepare | `migrate-connec-hub` |
| PostgreSQL | `postgres-connec-hub` |
| Redis | `redis-connec-hub` |
| Rede | `network-connec-hub` |
| Storage | `storage-connec-hub` |
| PostgreSQL data | `postgres-data-connec-hub` |
| Redis data | `redis-data-connec-hub` |

### Development/homologação

| Função | Service / container |
| --- | --- |
| Rails/Web | `rails-connec-hub-develop` |
| Sidekiq | `sidekiq-connec-hub-develop` |
| Migração/prepare | `migrate-connec-hub-develop` |
| PostgreSQL | `postgres-connec-hub-develop` |
| Redis | `redis-connec-hub-develop` |
| Rede | `network-connec-hub-develop` |
| Storage | `storage-connec-hub-develop` |
| PostgreSQL data | `postgres-data-connec-hub-develop` |
| Redis data | `redis-data-connec-hub-develop` |

Nos deployments embutidos, serviços `connect-*` continuam pertencendo à Connect|API e não recebem o sufixo do HUB.

## Deployments oficiais

```text
deployment/
├── production/
│   ├── standalone/
│   └── embedded-connect-api/
└── development/
    ├── standalone/
    └── embedded-connect-api/
```

`standalone` usa uma Connect|API externa.

`embedded-connect-api` coloca HUB + Connect|API na mesma stack, mas mantém persistências e imagens independentes.

## Imagens-base imutáveis do HUB

O HUB usa duas bases com ciclo de vida próprio:

```text
ghcr.io/wkarts/argws-connect-hub-build-base:1.0.0
ghcr.io/wkarts/argws-connect-hub-runtime-base:1.0.0
```

A versão vem de:

```text
docker/base/VERSION
```

A mesma base é usada por `develop` e por releases estáveis. Não existem bases `develop` e `production` diferentes.

Uma base é reconstruída somente quando `docker/base/**` muda ou quando o workflow é executado manualmente. A tag é imutável: se o conteúdo da definição mudar sem incremento de `docker/base/VERSION`, o workflow falha em vez de sobrescrever a tag existente.

### Build base

Contém toolchain e dependências de sistema necessárias para construir o HUB: Ruby/Ruby headers, compiladores, PostgreSQL development headers, Node/Yarn, Git, Vips development headers e Bundler.

### Runtime base

Contém somente dependências necessárias para executar a aplicação: Ruby, OpenSSL, timezone, PostgreSQL client, ImageMagick, Git, Vips e Bundler.

## Cache de dependências

O `docker/Dockerfile` copia `Gemfile/Gemfile.lock` e `package.json/yarn.lock` antes do restante do código. Dessa forma, alterações apenas em `app/`, `config/` etc. reutilizam as camadas de `bundle install` e `yarn install` pelo cache BuildKit/GitHub Actions.

Uma mudança em `Gemfile.lock` ou `yarn.lock` invalida somente a camada de dependências correspondente, sem reconstruir o sistema operacional/base.

## Validação sem imagem descartável

Pull requests para `develop` e `main` não constroem imagem Docker.

A validação executa:

- auditoria do HUB;
- sintaxe Ruby;
- sintaxe dos scripts Node de release;
- `bash -n` nos scripts shell;
- JSON básico de release/package;
- consistência da versão das imagens-base;
- `docker compose config` nos quatro deployments;
- validação dos nomes dos cinco serviços pertencentes ao HUB.

O build de imagem só ocorre após uma validação bem-sucedida em `develop` ou no fluxo de release da `main`.

## Fluxo develop

```text
push/merge develop
      │
      ├─ validação sem docker build
      │
      └─ build real uma vez
             │
             ├─ :develop
             └─ :sha-<commit>
```

Se uma nova versão de base estiver sendo publicada no mesmo push, o build da aplicação aguarda a disponibilidade das duas bases imutáveis.

## Fluxo release

```text
main
 │
 ├─ validar fonte/deployments (sem imagem)
 ├─ calcular SemVer
 ├─ validar SemVer/tag
 ├─ materializar VERSION/package/manifest
 ├─ configurar identidade Git
 ├─ persistir commit de versão [skip release]
 ├─ preflight de tag anotada
 ├─ construir/publicar imagem real UMA vez
 └─ criar tag + GitHub Release em job separado
```

O job de tag/release não constrói imagem. Se somente esse job falhar, ele pode ser reexecutado sem repetir o build da imagem.

## Correção do erro `Committer identity unknown`

Todo job que cria commit ou tag configura explicitamente uma identidade local:

```bash
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
```

A configuração não depende de outro job, pois cada job GitHub Actions executa em runner isolado.

Antes do build caro, o release cria e remove uma tag anotada local de preflight. Isso valida previamente a identidade do committer e o mecanismo de tag.

A criação final é idempotente: se a tag já existir no SHA esperado, ela é mantida; se apontar para outro SHA, o processo falha explicitamente. O mesmo tratamento é aplicado ao GitHub Release.

## Atualização de uma base

Quando Ruby/Alpine/Bundler/libs nativas precisarem mudar:

1. altere `docker/base/build/Dockerfile` e/ou `docker/base/runtime/Dockerfile`;
2. incremente `docker/base/VERSION`;
3. abra PR normalmente;
4. após merge em `develop`, o workflow publica a nova base;
5. o build `:develop` passa a utilizá-la;
6. quando `develop` for promovida a `main`, a mesma base já validada é reutilizada pela release.

Não vincule a versão da base à versão do HUB. Elas têm ciclos de vida independentes.
