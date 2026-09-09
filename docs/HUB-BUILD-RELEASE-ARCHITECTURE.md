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

## Serviços Connect|API embutidos

A Connect|API continua sendo uma plataforma independente. O sufixo identifica apenas a colocação dela dentro da stack do HUB e evita colisões de `service`/`container_name` com outras stacks.

### Produção

| Função | Service / container |
| --- | --- |
| API | `connect-api-hub` |
| Documentação | `docs-connect-api-hub` |
| PostgreSQL | `postgres-connect-api-hub` |
| Redis | `redis-connect-api-hub` |
| RabbitMQ | `rabbitmq-connect-api-hub` |
| MinIO | `minio-connect-api-hub` |
| NATS opcional | `nats-connect-api-hub` |
| ZooKeeper opcional | `zookeeper-connect-api-hub` |
| Kafka opcional | `kafka-connect-api-hub` |

### Development/homologação

| Função | Service / container |
| --- | --- |
| API | `connect-api-hub-develop` |
| Documentação | `docs-connect-api-hub-develop` |
| PostgreSQL | `postgres-connect-api-hub-develop` |
| Redis | `redis-connect-api-hub-develop` |
| RabbitMQ | `rabbitmq-connect-api-hub-develop` |
| MinIO | `minio-connect-api-hub-develop` |
| NATS opcional | `nats-connect-api-hub-develop` |
| ZooKeeper opcional | `zookeeper-connect-api-hub-develop` |
| Kafka opcional | `kafka-connect-api-hub-develop` |

Todos os hosts internos da Connect|API usam os mesmos nomes. Em produção, por exemplo, o HUB usa `http://connect-api-hub:8080`, e a API acessa `postgres-connect-api-hub`, `redis-connect-api-hub`, `rabbitmq-connect-api-hub` e `minio-connect-api-hub`. Em development são usados os equivalentes com `-develop`.

Os nomes lógicos dos volumes persistentes da Connect|API permanecem separados dos volumes do HUB. O Compose continua isolando os volumes pelo `COMPOSE_PROJECT_NAME` da stack.

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

`embedded-connect-api` coloca HUB + Connect|API na mesma stack, mas mantém persistências, serviços e imagens independentes.

## Família de imagens-base imutáveis do HUB

O HUB usa três bases com ciclo de vida próprio e uma única versão de infraestrutura:

```text
ghcr.io/wkarts/argws-connect-hub-build-base:1.1.0
ghcr.io/wkarts/argws-connect-hub-deps-base:1.1.0
ghcr.io/wkarts/argws-connect-hub-runtime-base:1.1.0
```

A versão vem de:

```text
docker/base/VERSION
```

A mesma família de bases é usada por `develop` e por releases estáveis. Não existem bases diferentes para development e production.

As tags são imutáveis. Se uma definição mudar mantendo uma tag já publicada, o workflow falha e exige incremento de `docker/base/VERSION`.

### Build base

Contém apenas a toolchain e bibliotecas de sistema necessárias para compilar dependências e assets: Ruby/Ruby headers, compiladores, PostgreSQL development headers, Node/Yarn, Git, Vips development headers e Bundler.

### Dependency base

Parte da build base e instala, uma única vez por definição de dependências:

- gems de `Gemfile.lock` em `/gems`;
- módulos de `yarn.lock` em `/app/node_modules`;
- pacotes próprios `packages/**`.

A definição da dependency base usa somente campos de dependência do `package.json`, evitando reconstrução apenas porque a versão SemVer do aplicativo mudou.

### Runtime base

Contém somente bibliotecas e executáveis necessários para executar o HUB em produção: Ruby, OpenSSL, timezone, PostgreSQL client, ImageMagick/Vips e Bundler. Git e toolchain de compilação não fazem parte do runtime.

## Quando cada base muda

`build-base` e `runtime-base` são publicados quando muda `docker/base/**` e a versão de base é incrementada.

`deps-base` também depende de:

- `Gemfile`;
- `Gemfile.lock`;
- dependências/resolutions/engines do `package.json`;
- `yarn.lock`;
- `packages/**`.

Uma alteração apenas em `app/`, `config/`, views, controllers ou outros arquivos da aplicação **não executa `bundle install` nem `yarn install`**.

## Build da aplicação

O `docker/Dockerfile` começa diretamente em `argws-connect-hub-deps-base`. Portanto um build normal faz essencialmente:

```text
copiar fonte do HUB
      ↓
compilar assets (produção)
      ↓
remover dependências exclusivas de build/dev
      ↓
copiar aplicação + gems para runtime-base
```

A imagem de produção remove os grupos Ruby `development/test` e remove `node_modules` depois do asset precompile. Development mantém o superset da dependency base.

## Validação sem imagem descartável

Pull requests para `develop` e `main` não constroem imagem Docker.

A validação executa:

- auditoria do HUB;
- sintaxe Ruby;
- sintaxe JavaScript dos scripts e pacotes próprios;
- `bash -n` nos scripts shell;
- JSON básico de release/package;
- política de dependências e namespaces;
- consistência da versão das imagens-base;
- `docker compose config` nos quatro deployments quando Docker Compose está disponível;
- validação dos nomes dos cinco serviços pertencentes ao HUB;
- validação do namespace completo dos serviços Connect|API nas variantes embutidas;
- validação de `container_name` explícito igual ao nome do serviço.

O build da imagem da aplicação só ocorre após validação bem-sucedida em `develop` ou no fluxo de release da `main`.

## Fluxo develop

```text
push/merge develop
      │
      ├─ validação sem docker build
      │
      ├─ se necessário: publicar nova base imutável
      │
      └─ build real da aplicação uma vez
             │
             ├─ :develop
             └─ :sha-<commit>
```

O build da aplicação aguarda `deps-base` e `runtime-base` da versão declarada em `docker/base/VERSION`.

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
 ├─ aguardar bases imutáveis
 ├─ construir/publicar imagem real UMA vez
 └─ criar tag + GitHub Release em job separado
```

O job de tag/release não constrói imagem. Se somente ele falhar, pode ser reexecutado sem repetir o build da imagem.

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

Quando Ruby/Alpine/Bundler/libs nativas ou dependências do HUB precisarem mudar:

1. altere a definição necessária;
2. incremente `docker/base/VERSION` se a tag atual já estiver publicada;
3. abra PR normalmente;
4. a PR valida fonte e definições sem montar imagem descartável;
5. após merge, o workflow publica a nova família de bases necessária;
6. o build da aplicação passa a reutilizar as bases publicadas;
7. a mesma versão de base segue para a release.

Não vincule a versão da base à versão do HUB. Aplicação e infraestrutura têm ciclos de vida independentes.
