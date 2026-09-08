# HUB — privacidade e telemetria

Esta distribuição remove SDKs e agentes de analytics/APM de terceiros do runtime e do build: June/Segment Analytics, Sentry, Datadog/ddtrace, New Relic, Elastic APM, Scout APM, PostHog, Mixpanel, Amplitude, Google Analytics/gtag/GTM e Meta/Facebook Pixel.

`AnalyticsHelper` permanece apenas como shim local sem operações para compatibilidade com componentes legados e não transmite eventos.

O antigo serviço de hub/registro externo foi convertido em `HubPlatform`, implementação local sem chamadas de rede. Scripts arbitrários de dashboard não são injetados pela distribuição.

Integrações explicitamente configuradas pelo administrador (Connect|API, SMTP/IMAP, webhooks, storage, Facebook/Instagram como canal etc.) continuam realizando as comunicações funcionais necessárias e não são classificadas como telemetria.
