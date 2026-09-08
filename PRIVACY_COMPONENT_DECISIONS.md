# HUB — decisões de privacidade e ferramentas internas

## Mantidos/restaurados

- `.storybook/main.js` e `.storybook/preview.js`: ambiente interno de desenvolvimento de componentes. Telemetria do Storybook é forçada a OFF.
- `.github/workflows/publish_codespace_image.yml`: CI de desenvolvimento, publica somente no GHCR do projeto.
- SLA, reports, events, factories e specs funcionais: fazem parte do comportamento/testes internos do HUB e não são classificados como telemetria por nome.
- WebPush/FCM: integrações funcionais configuradas pelo administrador, não analytics de produto.

## Removidos

- `app/javascript/dashboard/helper/AnalyticsHelper/`: analytics de uso/identidade herdado.
- `spec/factories/clearbit_response.rb`: fixture órfã da integração Clearbit não distribuída no HUB.
- `spec/lib/hub_hub_spec.rb`: testava PING/registro/eventos remotos e não representa mais a arquitetura do HUB.
- Barnes/StatsD e SDKs de analytics/APM de terceiros.

## Substituições

- `spec/lib/hub_platform_spec.rb`: garante identificador local estável e ausência de POST/GET externos.
- `Internal::CheckNewVersionsJob`: preservado como compatibilidade local/no-op; spec confirma que não consulta serviço remoto.
- `HubExceptionTracker`: logger local compatível com metadados existentes; não envia exceções para terceiros.
