# HUB ↔ Connect|API

Release validada contra **ARGWS Connect API 1.0.21**.

O HUB usa somente **Connect|API** como provider visível de WhatsApp. A Connect|API provisiona a sessão WhatsApp por QR Code ou código de pareamento e expõe a façade Meta-compatible usada pelo HUB.

Contratos esperados:
- `POST /instance/create`
- `GET /instance/connect/:instanceName`
- `GET /instance/connectionState/:instanceName`
- `DELETE /instance/logout/:instanceName`
- `PUT /compat/meta/:instanceName`
- `POST /graph/:version/:phoneNumberId/messages`
- `POST /graph/:version/:phoneNumberId/media`
- `GET /graph/:version/:mediaId`
- `GET /graph/:version/:businessAccountId/message_templates`

O token administrativo configurado em `CONNECT_API_AUTH_TOKEN` é usado somente pelo backend do HUB para provisionamento. Cada inbox recebe uma credencial própria, que não é serializada para o navegador.
