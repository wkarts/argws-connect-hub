# HUB 1.0.0 — Integração Connect|API Next

## Base desta entrega

- HUB: `HUB-1.0.0-develop-completo-corrigido`.
- Connect|API: branch/pacote `develop` fornecido para a próxima release.
- O HUB não faz migração automática das instâncias já existentes.

## Providers internos da Connect|API

A caixa continua sendo `provider=connectapi` para o HUB. O protocolo interno da instância Connect|API passa a ser persistido em `provider_config.connect_api_provider`:

- `WHATSAPP-BAILEYS`: mensageria e compatibilidade histórica.
- `WHATSAPP-ZAPO`: mensageria + chamadas de voz.

O default de compatibilidade continua `WHATSAPP-BAILEYS`. Novas caixas permitem escolher ZAPO explicitamente.

## Chamadas no HUB

Foi adicionada uma API Rails server-side por conversa:

- `GET /api/v1/accounts/:account_id/conversations/:conversation_id/connect_api_calls`
- `POST /api/v1/accounts/:account_id/conversations/:conversation_id/connect_api_calls`
- `POST .../connect_api_calls/accept`
- `POST .../connect_api_calls/reject`
- `POST .../connect_api_calls/end_call`
- `POST .../connect_api_calls/mute`
- `POST .../connect_api_calls/media_ticket`

O token administrativo e o token persistente da instância nunca são retornados ao frontend.

A listagem e os comandos de chamada são vinculados ao telefone do contato da conversa. Um agente não recebe pela API da conversa chamadas de outro contato da mesma instância.

No cabeçalho da conversa, instâncias ZAPO recebem um painel de chamada com:

- detecção periódica de chamada recebida da conversa atual;
- iniciar chamada;
- atender;
- recusar;
- silenciar/reativar microfone;
- encerrar;
- estado do áudio;
- captura de microfone e reprodução de PCM mono 16 kHz.

Vídeo permanece explicitamente desabilitado.

## Voice Media Ticket

Para não expor credenciais persistentes no navegador, esta entrega depende da extensão incluída no pacote Connect|API desta mesma entrega:

`POST /call/mediaTicket/{instanceName}`

Fluxo:

1. HUB chama o endpoint no backend usando `CONNECT_API_AUTH_TOKEN`.
2. Connect|API valida que o `callId` está ativo e que o provider possui mídia de voz.
3. Connect|API retorna ticket aleatório, de uso único, com 30 segundos de validade.
4. HUB retorna ao navegador apenas o ticket e a URL `wss://.../voice/media`.
5. O browser abre o WebSocket e autentica com `{ "ticket": "..." }`.

O modo legado de autenticação do WebSocket por token foi mantido na Connect|API para não quebrar clientes anteriores, mas o HUB e o Manager atualizado usam ticket.

### Escala horizontal

O armazenamento atual de tickets é local ao processo Connect|API. Em múltiplas réplicas, mantenha afinidade entre a emissão do ticket e o WebSocket `/voice/media`, ou evolua o storage de tickets para Redis antes de remover sticky sessions.

## Limite de chamadas simultâneas

- Teto global: `ZAPO_VOIP_MAX_CONCURRENT_CALLS` na Connect|API.
- Limite por instância: `voipMaxConcurrentCalls` na Connect|API / `voip_max_concurrent_calls` no `provider_config` do HUB.
- Connect|API é a autoridade final e rejeita valores acima do teto global.
- HUB Admin permite administrar o limite de uma instância ZAPO vinculada ao HUB.

## HUB Admin / Connect|API

Nova área Super Admin: `Connect|API`.

Exibe:

- versão da Connect|API;
- total de instâncias na instalação;
- quantidade vinculada ao HUB;
- quantidade conectada;
- quantidade com chamadas;
- nome, profile, número, provider e status;
- contagem de contatos, chats e mensagens;
- capacidade de chamadas/voz;
- limite de chamadas por instância e teto global.

Para instâncias vinculadas ao HUB permite:

- reiniciar;
- desconectar;
- dry-run de migração Baileys ↔ ZAPO;
- migrar Baileys ↔ ZAPO explicitamente;
- alterar limite de chamadas ZAPO.

Instâncias da mesma Connect|API que não estejam vinculadas a uma caixa do HUB são mostradas somente como inventário e não podem ser alteradas pelo HUB Admin.

A exclusão definitiva continua disponível na API administrativa da Connect|API, mas não foi colocada como botão de um clique no HUB Admin.

## Deployment

Veja `deployment/README.md`.

São fornecidas quatro variantes:

1. produção + Connect|API externa;
2. produção + Connect|API embutida;
3. development/homologação + Connect|API externa;
4. development/homologação + Connect|API embutida.

No modo embutido:

- HUB PostgreSQL é separado do PostgreSQL Connect|API;
- HUB Redis é separado do Redis Connect|API;
- Connect|API possui RabbitMQ e MinIO próprios;
- NATS e Kafka estão disponíveis por profiles opcionais;
- HUB usa `http://connect-api:8080` internamente;
- browser usa `CONNECT_API_PUBLIC_URL` para mídia WebSocket;
- todos os volumes são independentes.

## Variáveis novas/expandidas no HUB

```dotenv
CONNECT_API_BASE_URL=
CONNECT_API_PUBLIC_URL=
CONNECT_API_MANAGER_PUBLIC_URL=
CONNECT_API_AUTH_TOKEN=
CONNECT_API_REQUEST_TIMEOUT=60
CONNECT_API_DEFAULT_PROVIDER=WHATSAPP-BAILEYS
```

## Compatibilidade

- Nenhuma instância Baileys existente é convertida automaticamente.
- A camada Meta-compatible de mensagens continua sendo utilizada.
- Tokens de instância continuam omitidos dos JSONs de inbox.
- A integração de chamadas usa o backend Rails como plano de controle e o Voice Media Gateway somente como plano de mídia.
