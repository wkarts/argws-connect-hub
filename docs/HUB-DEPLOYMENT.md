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
