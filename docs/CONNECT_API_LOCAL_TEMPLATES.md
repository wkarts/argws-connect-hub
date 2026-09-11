# Integração de templates Connect|API no HUB

## Dependências

A Connect|API é a origem do catálogo. Atualize a API e aplique suas migrations,
atualize Manager/DOCs e depois atualize **web e Sidekiq do HUB juntos**. Não há
migration nova no HUB: o catálogo continua no JSONB do canal e as preferências de
abertura mantêm o desenho existente.

As requisições de templates usam o token da instância armazenado em
`provider_config['api_key']`, como Bearer no Graph, sem alternativa global.

## Contrato

`connectapi_local` permanece apenas como origem técnica. Para o consumidor, os
templates chegam com:

```json
{
  "status": "APPROVED",
  "approved": true,
  "category": "OPENING",
  "enabled": true,
  "available": true
}
```

`enabled` e `available` controlam a disponibilidade operacional. O status de
aprovação permanece `APPROVED`.

A categoria `OPENING` é apresentada no HUB como **Abertura de conversa**.

A importação usa `/graph/{version}/{businessAccountId}/message_templates`. O HUB
não cria `hello`: recebe o registro real criado na Connect|API com o texto inicial
“Olá! Como podemos ajudar?”. No primeiro catálogo somente `hello` fica liberado
para abertura. Outros templates podem ser liberados pelo administrador da caixa.

Uma revisão não altera as preferências de habilitação. Remoção/desativação remota
impede a seleção sem apagar a escolha administrativa anterior. Um template
arquivado na API não é recriado pela consulta.

O seletor e a tela de configuração exibem somente o nome, idioma e a categoria de
uso. A prévia inclui HEADER/BODY/FOOTER quando houver. O BODY suporta variáveis
posicionais consecutivas; o frontend envia nome, idioma, parâmetros e
`connect_api_version`.

A API é a autoridade final: renderiza o cadastro persistido e envia pela mesma
instância. Revisão diferente retorna conflito; não há fallback livre, troca de
credencial nem repetição HTTP automática em caso de erro. Um retorno sem ID não é
tratado como confirmação.

## Uso

1. Na Connect|API: Instâncias → instância → Modelos de mensagem. Confirme `hello`
   e crie/edite outros templates.
2. No HUB: Configurações → Caixas de entrada → caixa → Configuração da Connect|API
   → Reconciliar agora.
3. Em Templates de abertura, mantenha `hello` ou libere outros templates.
4. Em Nova conversa, selecione o template, preencha as variáveis e confira a prévia.

A categoria visual dos templates dessa integração é **Abertura de conversa**.

Não há alteração em conversas existentes, contatos, fluxo de chamadas ou
armazenamento S3/MinIO. Templates de mídia/botões não fazem parte desta primeira
entrega.

## Testes

```bash
ruby scripts/test-connect-api-opening-templates.rb
node --test scripts/test-connect-api-opening-templates.mjs
ruby scripts/test-connect-api-local-templates.rb
node --test scripts/test-connect-api-local-templates.mjs
bundle exec rspec spec/services/whatsapp/providers/connect_api_local_templates_spec.rb
```

O workflow HUB Quality executa os contratos de catálogo, interface e envio sem
retirar os testes anteriores.
