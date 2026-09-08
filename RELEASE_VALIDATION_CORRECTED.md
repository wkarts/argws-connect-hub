# HUB 1.0.0 develop — validação da versão completa corrigida

## Resultado

- `HUB AUDIT: OK`
- Ruby: **1121 arquivos** verificados com `ruby -c`, sem erro de sintaxe.
- Workflows GitHub Actions: YAML válido.
- `package.json`, `RELEASE-MANIFEST.json` e `public/manifest.json`: JSON válido.
- Storybook restaurado e com telemetria forçada a OFF.
- Codespace workflow restaurado, GHCR-only e AMD64.
- Docker Actions em releases Node 24: `setup-buildx-action@v4.3.0`, `build-push-action@v7.3.0`, `login-action@v4`.
- `AnalyticsHelper`, `$track`, `useTrack`, `HubHub` e fixture Clearbit órfã: ausentes.
- `HubPlatform` possui spec de privacidade garantindo ausência de POST/GET remotos.
- `HubExceptionTracker` registra somente no Rails logger local e aceita os metadados dos call sites existentes.
- `Internal::CheckNewVersionsJob` não consulta serviço remoto.
- IMAP Sent: observer carrega explicitamente no boot e delega o APPEND ao `Imap::SentMailAppendService`.
- Branding HUB/PWA/favicons preservados.

## Observação sobre Storybook

Storybook é ferramenta **somente de desenvolvimento**, não telemetria do produto. Sua dependência transitiva de telemetry pode existir no lockfile da ferramenta, mas a coleta fica explicitamente desativada tanto em `.storybook/main.js` (`disableTelemetry: true`) quanto no runner (`STORYBOOK_DISABLE_TELEMETRY=1`). O runtime do HUB não carrega esse SDK.

## Limite da validação local

Este ambiente não possui o executável `bundle`, então não foi possível executar RSpec ou o `assets:precompile` completo localmente. O pacote preserva os gates de GitHub Actions/Docker para executar esses testes no ambiente de CI com Ruby 3.3.10.
