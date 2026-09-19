# HUB — implantação GHCR / AMD64

## Imagem da aplicação

- Produção: `ghcr.io/wkarts/argws-connect-hub:latest`
- Development/homologação: `ghcr.io/wkarts/argws-connect-hub:develop`
- Arquitetura de publicação: `linux/amd64`

PostgreSQL e Redis do HUB permanecem nas imagens de infraestrutura já utilizadas pelo projeto:

- `ghcr.io/wkarts/hub-postgres:16-alpine`
- `ghcr.io/wkarts/hub-redis:7-alpine`

## Deployments prontos

Use `deployment/README.md` como documento canônico desta entrega.

Há quatro variantes:

- `deployment/production/standalone`
- `deployment/production/embedded-connect-api`
- `deployment/development/standalone`
- `deployment/development/embedded-connect-api`

Cada diretório contém `compose.yaml` e `.env.example` próprios.

## Connect|API externa

```env
CONNECT_API_BASE_URL=https://connect.exemplo.com
CONNECT_API_PUBLIC_URL=https://connect.exemplo.com
CONNECT_API_MANAGER_PUBLIC_URL=https://connect.exemplo.com/manager
CONNECT_API_AUTH_TOKEN=troque-por-token-forte
CONNECT_API_REQUEST_TIMEOUT=60
CONNECT_API_DEFAULT_PROVIDER=WHATSAPP-BAILEYS
```

`CONNECT_API_AUTH_TOKEN` é utilizado somente pelo backend do HUB.

## Connect|API embutida

No modo embutido, o HUB fala com `http://connect-api:8080` pela rede Docker. O domínio público da Connect|API continua obrigatório para Manager e para `wss://.../voice/media`.

PostgreSQL/Redis do HUB nunca são compartilhados com PostgreSQL/Redis da Connect|API. A Connect|API também possui RabbitMQ e MinIO próprios, com NATS/Kafka opcionais por profile.

O proxy reverso do domínio da Connect|API precisa permitir WebSocket Upgrade em `/voice/media`.


## Diagnóstico e mitigação no HUB Admin

Os deployments atuais incluem um volume compartilhado de diagnóstico para Rails e Sidekiq:

```env
HUB_DIAGNOSTICS_ENABLED=true
HUB_DIAGNOSTICS_DIR=/app/log/hub_diagnostics
HUB_DIAGNOSTICS_FILE_BYTES=8388608
HUB_DIAGNOSTICS_FILE_COUNT=8
HUB_DIAGNOSTICS_RETENTION_SECONDS=259200
HUB_DIAGNOSTICS_DATA_PATH=./volumes/diagnostics
HUB_CONNECT_RELIABILITY_ENABLED=true
HUB_EXISTING_INSTANCE_BINDING_ENABLED=true
```

O painel **HUB Admin → Diagnóstico e logs** lê esse diretório compartilhado. O conteúdo é rotacionado e sanitizado; não substitui os logs brutos do Docker, PostgreSQL, Redis ou da Connect|API.

`HUB_CONNECT_RELIABILITY_ENABLED=true` ativa o processamento individual de eventos Connect|API, retenção de status antecipado e as proteções de concorrência. `HUB_EXISTING_INSTANCE_BINDING_ENABLED=true` libera o fluxo administrativo para associar uma caixa a uma instância Connect|API já existente sem criar ou parear uma nova sessão.
