# HUB — Deployment

Este diretório contém quatro variantes independentes, prontas para Dockge/Portainer/Compose:

- `production/standalone`: HUB em produção apontando para uma Connect|API externa.
- `production/embedded-connect-api`: HUB + Connect|API na mesma stack, com PostgreSQL/Redis separados e RabbitMQ/MinIO próprios da Connect|API.
- `development/standalone`: canal `develop` do HUB apontando para Connect|API externa de desenvolvimento/homologação.
- `development/embedded-connect-api`: imagens `develop` de HUB/Connect|API na mesma stack.

A Connect|API continua sendo uma plataforma separada. O deployment embutido apenas coloca os serviços das duas plataformas na mesma rede/stack; não compartilha imagem, banco, Redis ou ciclo de release.

A variante `development` usa a imagem `:develop` do HUB, porém mantém Rails em runtime `production`, permitindo homologar a mesma forma de execução que será promovida.

## Identidade dos serviços HUB

Produção:

```text
rails-connec-hub
sidekiq-connec-hub
migrate-connec-hub
postgres-connec-hub
redis-connec-hub
```

Development/homologação:

```text
rails-connec-hub-develop
sidekiq-connec-hub-develop
migrate-connec-hub-develop
postgres-connec-hub-develop
redis-connec-hub-develop
```

As redes mantêm nomes próprios para produção e development. Os dados persistentes usam bind mounts configuráveis e, por padrão, ficam dentro da pasta de cada stack em `./volumes/...`.

## Persistência dos dados

Os deployments atuais não dependem de volumes Docker nomeados para dados persistentes. Cada serviço grava em uma pasta visível junto do deployment, facilitando backup, inspeção e migração do projeto completo.

HUB:

```text
./volumes/storage
./volumes/postgres
./volumes/redis
```

No deployment com Connect|API embutida também são usados:

```text
./volumes/connect-api/instances
./volumes/connect-api/postgres
./volumes/connect-api/redis
./volumes/connect-api/rabbitmq
./volumes/connect-api/minio
./volumes/connect-api/nats
./volumes/connect-api/zookeeper/data
./volumes/connect-api/zookeeper/log
./volumes/connect-api/kafka
```

Todos esses caminhos podem ser sobrescritos pelas variáveis `*_DATA_PATH` documentadas no `.env.example`. Os caminhos internos dos containers permanecem os caminhos nativos de cada serviço.

O diretório `volumes/` está ignorado pelo Git para impedir que bancos, filas, objetos, sessões ou mídias sejam adicionados ao repositório.

## Migração de instalações que usavam volumes nomeados

Instalações criadas com versões anteriores podem possuir dados em volumes Docker nomeados. Não suba diretamente o compose novo com diretórios vazios, porque o PostgreSQL/Redis poderá inicializar uma estrutura nova e dar a impressão de perda dos dados anteriores.

O utilitário `migrate-named-volumes-to-bind.sh` copia os dados existentes para os novos bind mounts. Ele não remove os volumes antigos e aborta quando encontra a stack em execução ou um destino que já contenha dados.

Exemplo para produção standalone:

```bash
cd deployment/production/standalone
docker compose down
cd ../..
./migrate-named-volumes-to-bind.sh production-standalone
cd production/standalone
docker compose up -d
```

Variantes disponíveis:

```text
production-standalone
production-embedded
development-standalone
development-embedded
```

Se o deployment estiver fora da árvore do repositório, informe o diretório como segundo argumento:

```bash
./migrate-named-volumes-to-bind.sh production-embedded /opt/stacks/connec-hub
```

Nunca use `docker compose down -v` durante a migração. Depois de validar a aplicação, bancos, arquivos e sessões no novo deployment, os volumes Docker antigos podem ser removidos manualmente conforme a política operacional do ambiente.

## Identidade dos serviços Connect|API embutidos

A Connect|API mantém identidade própria mesmo quando sobe junto com o HUB. Para evitar colisões com outras stacks, todos os containers embutidos recebem nomes explícitos.

Produção:

```text
connect-api-hub
docs-connect-api-hub
postgres-connect-api-hub
redis-connect-api-hub
rabbitmq-connect-api-hub
minio-connect-api-hub
nats-connect-api-hub
zookeeper-connect-api-hub
kafka-connect-api-hub
```

Development/homologação:

```text
connect-api-hub-develop
docs-connect-api-hub-develop
postgres-connect-api-hub-develop
redis-connect-api-hub-develop
rabbitmq-connect-api-hub-develop
minio-connect-api-hub-develop
nats-connect-api-hub-develop
zookeeper-connect-api-hub-develop
kafka-connect-api-hub-develop
```

Os nomes acima são tanto os `services` quanto os `container_name` da variante embutida. A persistência da Connect|API continua isolada da persistência do HUB, agora em subdiretórios próprios de `./volumes/connect-api/`.

## Domínios

Os `.env.example` usam ARGWS apenas como exemplo. Troque:

- `FRONTEND_URL` — domínio público do HUB;
- `CONNECT_API_PUBLIC_URL` — domínio público da Connect|API;
- `CONNECT_API_MANAGER_PUBLIC_URL` — normalmente `${CONNECT_API_PUBLIC_URL}/manager`.

No modo embutido, em produção o HUB fala com `http://connect-api-hub:8080`; em development usa `http://connect-api-hub-develop:8080`. O navegador usa somente a URL pública para o WebSocket de mídia.

## Proxy reverso / CloudPanel

Produção, defaults:

- HUB: `127.0.0.1:3000` → `https://hub.argws.com.br`
- Connect|API embutida: `127.0.0.1:38080` → `https://connect.argws.com.br`
- Docs Connect|API: `127.0.0.1:38082` → domínio de documentação opcional

Development/homologação, defaults: HUB `33000`, Connect|API `39080`, Docs `39082`.

O proxy da Connect|API deve permitir WebSocket Upgrade, inclusive em `/voice/media`, para chamadas com áudio no navegador.

## Chamadas

- Baileys permanece compatível e é o default histórico.
- ZAPO habilita chamadas de voz.
- `ZAPO_VOIP_MAX_CONCURRENT_CALLS` define o teto global na Connect|API.
- O HUB Admin pode definir o limite por instância, nunca acima do teto global.
- O navegador recebe apenas ticket temporário de mídia; `CONNECT_API_AUTH_TOKEN` permanece no backend.

## NATS/Kafka opcionais

No modo embutido, os serviços estão sob profiles:

```bash
docker compose --profile nats up -d
docker compose --profile kafka up -d
docker compose --profile extended up -d
```

Além do profile, habilite `CONNECT_NATS_ENABLED=true` e/ou `CONNECT_KAFKA_ENABLED=true` no `.env`.

## Primeira subida

1. Copie `.env.example` para `.env`.
2. Substitua todos os `CHANGE_ME_*` por segredos exclusivos.
3. Ajuste os domínios.
4. Confirme se os caminhos `*_DATA_PATH` estão adequados; os defaults usam `./volumes/...`.
5. Execute `docker compose pull && docker compose up -d`.
6. Produção standalone: acompanhe `docker compose logs -f migrate-connec-hub rails-connec-hub sidekiq-connec-hub`.
7. Development standalone: use os mesmos nomes com `-develop`.
8. Na variante embutida de produção, acompanhe também `connect-api-hub` quando necessário.
9. Na variante embutida de development, use `connect-api-hub-develop`.

Os bancos e Redis do HUB nunca são compartilhados com a Connect|API na variante embutida.
