# HUB 1.0.0 develop — validação Connect|API Next

Data: 2026-09-08

## Resultado

- `scripts/audit-hub.sh`: **HUB AUDIT: OK**.
- Ruby: **1131 arquivos `.rb`** verificados com `ruby -c`, sem erro de sintaxe.
- Novos controllers/services/rotas: sintaxe Ruby OK.
- Views ERB alteradas do Super Admin: compilação Ruby via `erb -x` OK.
- JavaScript novo de chamadas/Voice Media: `node --check` OK.
- Scripts das quatro views Vue alteradas: `node --check` OK após extração do bloco `<script>`.
- `config/installation_config.yml`: YAML válido.
- Quatro `compose.yaml` de deployment: YAML válido.
- Dependências entre serviços, volumes declarados e variáveis de Compose: validação estrutural OK.
- Cinco `.env.example` relevantes: sem chaves duplicadas.
- Contratos OpenAPI/AsyncAPI da Connect|API modificada: `generate-openapi.mjs --check` OK.
- CSP do HUB: não existe `connect-src` ativo que bloqueie o WebSocket externo de mídia.

## Validações funcionais de contrato executadas por inspeção

- Endpoints de chamada utilizados pelo HUB correspondem às rotas da Connect|API develop fornecida.
- `WHATSAPP-ZAPO` é o provider atual com chamadas/voz; Baileys permanece compatível para mensageria.
- Migração Baileys ↔ ZAPO usa o endpoint nativo `migrateProvider` e não ocorre automaticamente.
- Alteração do limite VOIP preserva `rejectCall`, `groupsIgnore`, `alwaysOnline`, `readMessages`, `readStatus`, `syncFullHistory` e `msgCall` antes de chamar `/settings/set`.
- Tokens administrativos e tokens persistentes de instância não são renderizados na UI de chamadas nem no HUB Admin.
- Chamadas da API de uma conversa são filtradas/validadas contra o telefone do contato daquela conversa.
- O Voice Media Ticket é emitido apenas para `callId` ativo e é consumido uma única vez.

## Deployment embutido

Foram preservados explicitamente os defaults operacionais relevantes da Connect|API develop, inclusive `DATABASE_SAVE_*`, Redis, S3 e migrações. Assim, o deployment reduzido do HUB não cai inadvertidamente nos defaults `false` de persistência da Connect|API.

## Limites da validação local

O pacote fornecido não contém `node_modules`, e este ambiente não possui `bundle`/gems do projeto nem Docker CLI. Por isso não foi possível executar localmente:

- `bundle exec rspec`;
- `assets:precompile` completo;
- build completo do frontend;
- `docker compose config`/subida real dos containers.

Esses gates devem permanecer obrigatórios no GitHub Actions antes da promoção para `main`/release. A validação estática e contratual descrita acima foi concluída com sucesso.
