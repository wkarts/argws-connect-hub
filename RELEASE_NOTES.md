# HUB 1.0.0 develop — Connect|API Next

Base: `HUB-1.0.0-develop-completo-corrigido`.

## Integração Connect|API

- Preserva a integração Meta-compatible de mensagens existente.
- Novas caixas Connect|API podem escolher `WHATSAPP-BAILEYS` ou `WHATSAPP-ZAPO`.
- Instâncias existentes não são migradas automaticamente.
- ZAPO habilita chamadas de voz diretamente na conversa do HUB.
- O HUB controla listar/iniciar/atender/recusar/silenciar/encerrar chamadas no backend Rails.
- O áudio do navegador usa ticket temporário, aleatório, de uso único e curta duração; tokens persistentes não são enviados ao browser.
- Vídeo permanece desabilitado porque o provider ZAPO desta develop disponibiliza voz, não vídeo.
- O limite de chamadas simultâneas pode ser definido por instância, respeitando `ZAPO_VOIP_MAX_CONCURRENT_CALLS` da Connect|API.

## HUB Admin

Nova área `Connect|API` no Super Admin com inventário e administração das instâncias vinculadas ao HUB:

- versão e disponibilidade da Connect|API;
- provider, status, número, perfil e contadores;
- vínculo com empresa/inbox do HUB;
- capacidade de chamadas e limite VOIP;
- reinício e desconexão;
- dry-run e migração explícita Baileys ↔ ZAPO;
- ajuste do limite VOIP preservando as demais configurações da instância;
- acesso ao Manager completo da Connect|API.

Instâncias existentes na mesma Connect|API, mas não vinculadas ao HUB, aparecem somente como inventário e não podem ser alteradas pelo HUB Admin.

## Deployment

Foram adicionadas quatro variantes em `deployment/`:

1. `production/standalone` — HUB + Connect|API externa;
2. `production/embedded-connect-api` — HUB + Connect|API na mesma stack;
3. `development/standalone` — imagem develop do HUB + Connect|API externa;
4. `development/embedded-connect-api` — imagens develop do HUB e Connect|API na mesma stack.

Na modalidade embutida, HUB e Connect|API possuem PostgreSQL, Redis e volumes separados. RabbitMQ e MinIO são exclusivos da Connect|API; NATS e Kafka são profiles opcionais.

## Baseline preservada

- Branding HUB/PWA/favicons da versão corrigida.
- Privacidade: sem analytics/APM/telemetria externa no runtime do HUB.
- Storybook e ferramentas de desenvolvimento preservados com telemetria desabilitada.
- IMAP/SMTP genérico, `BODY.PEEK[]` e APPEND em Sent preservados.
- GHCR / `linux/amd64` e fluxo `develop → main` preservados.
