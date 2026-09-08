# 🅷🆄🅱

## Release

**3.12.8-hub.1** — Comunicação sem limites.

HUB é uma central omnichannel autogerenciada para atendimento e colaboração.

## Canais desta distribuição

- **WhatsApp — Connect|API**: QR Code, código de pareamento, envio/recebimento, mídia, replies, reactions e compatibilidade Meta Cloud fornecida pela própria Connect|API.
- **E-mail — IMAP/SMTP**: recebe e envia usando servidores padrão (Mailcow, Dovecot/Postfix, cPanel, Plesk, Gmail/Microsoft via OAuth quando configurados). O servidor IMAP permanece como fonte física/autoridade da caixa postal; o HUB mantém os registros de conversa necessários para atendimento sem remover a mensagem remota.
- Demais canais do núcleo open-source permanecem disponíveis quando configurados.

## Privacidade

Esta distribuição não inclui telemetria privada, analytics de produto ou APM de terceiros. June, Segment Analytics, Sentry, Datadog, New Relic, Elastic APM e Scout APM foram removidos do runtime/build.

## Connect|API

Configure no servidor HUB:

```env
CONNECT_API_BASE_URL=https://api.connect.exemplo.com
CONNECT_API_AUTH_TOKEN=troque-pelo-token-global-da-connect-api
```

O token global é usado somente no backend para provisionamento. Cada inbox recebe uma credencial própria para operar sua instância e a façade Meta-compatible `/graph`.

## E-mail

Cada inbox de e-mail pode usar IMAP e SMTP próprios. A sincronização IMAP usa `BODY.PEEK[]` para não marcar mensagens como lidas apenas por sincronizá-las. Em contas IMAP/SMTP genéricas, mensagens entregues com sucesso por SMTP são anexadas à pasta remota de enviados.

## Containers

A distribuição está preparada para publicação AMD64 no GitHub Container Registry (GHCR). Consulte `docs/HUB-DEPLOYMENT.md`.

## Licença

O núcleo comunitário continua sob os termos de sua licença open-source aplicável e preserva os avisos legais do upstream. O diretório Enterprise do upstream não faz parte deste pacote redistribuível.
