# HUB — Deployment

Este diretório contém quatro variantes independentes, prontas para Dockge/Portainer/Compose:

- `production/standalone`: HUB em produção apontando para uma Connect|API externa.
- `production/embedded-connect-api`: HUB + Connect|API na mesma stack, com PostgreSQL/Redis separados e RabbitMQ/MinIO próprios da Connect|API.
- `development/standalone`: canal `develop` do HUB apontando para Connect|API externa de desenvolvimento/homologação.
- `development/embedded-connect-api`: imagens `develop` de HUB/Connect|API na mesma stack.

A variante `development` usa imagens da branch `develop`, porém mantém Rails em runtime `production`, que é a forma correta de homologar a imagem que será promovida sem depender de gems/dev-server locais.

## Domínios

Os `.env.example` usam ARGWS como exemplo. Troque somente:

- `FRONTEND_URL` — domínio público do HUB.
- `CONNECT_API_PUBLIC_URL` — domínio público da Connect|API.
- `CONNECT_API_MANAGER_PUBLIC_URL` — normalmente `${CONNECT_API_PUBLIC_URL}/manager`.

No modo embutido, o HUB fala com `http://connect-api:8080` internamente e o navegador usa apenas a URL pública para o WebSocket de mídia.

## Proxy reverso / CloudPanel

Produção, defaults:

- HUB: `127.0.0.1:3000` → `https://hub.argws.com.br`
- Connect|API embutida: `127.0.0.1:38080` → `https://connect.argws.com.br`
- Docs Connect|API: `127.0.0.1:38082` → domínio de documentação opcional

Development/homologação, defaults: HUB `33000`, Connect|API `39080`, Docs `39082`.

O proxy da Connect|API **deve permitir WebSocket Upgrade**, inclusive em `/voice/media`, para chamadas com áudio no navegador.

## Chamadas

- Baileys permanece compatível e é o default histórico.
- ZAPO habilita chamadas de voz.
- `ZAPO_VOIP_MAX_CONCURRENT_CALLS` define o teto global na Connect|API.
- O HUB Admin pode definir o limite por instância, nunca acima do teto global.
- O navegador recebe apenas um ticket temporário de mídia; `CONNECT_API_AUTH_TOKEN` permanece no backend.

## NATS/Kafka opcionais

No modo embutido, os serviços estão sob profiles. Exemplos:

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
4. Execute `docker compose pull && docker compose up -d`.
5. Acompanhe `docker compose logs -f hub-migrate hub connect-api` (no standalone não existe `connect-api`).

Os bancos e Redis do HUB nunca são compartilhados com a Connect|API na variante embutida.
