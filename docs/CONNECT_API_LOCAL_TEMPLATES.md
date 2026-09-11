# Integração de modelos locais Connect|API no HUB

## Dependências

Esta alteração complementa a entrega de modelos locais da Connect|API. Atualize a
API e aplique suas migrations, atualize Manager/DOCs e depois atualize **web e
Sidekiq do HUB juntos**. Não é necessária migration no HUB: o catálogo continua no
JSONB do canal e as preferências mantêm o desenho existente.

A base do HUB é `develop` em `1439d0ab93cdb77de098ae4e7461e8583d2f2747`.
Não altere `CONNECT_API_AUTH_TOKEN` para colocar ali uma credencial individual.
As novas requisições de modelos usam o token da instância armazenado em
`provider_config['api_key']`, como Bearer no Graph, sem alternativa global.

Este pacote **não conclui a revisão geral das credenciais nativas**: envio comum
de texto/mídia, recuperação nativa e chamadas mantêm a implementação preexistente.
A separação completa dessas operações administrativas/operacionais continua sendo
uma mudança independente. O código oficial Cloud compartilhado não é refatorado.

## Funcionamento

`connectapi_local` identifica os modelos próprios. São elegíveis somente com
`LOCAL_READY`, `execution=rendered_text`, `meta_approved=false`, habilitados,
disponíveis e com versão válida. Não é utilizado `APPROVED` fictício.

A importação permanece na rota `/graph/{version}/{businessAccountId}/message_templates`.
O HUB não cria `hello`: recebe o registro real, criado na API com o texto inicial
“Olá! Como podemos ajudar?”. No primeiro catálogo somente `hello` fica liberado
para abertura. Outros modelos são liberados pelo administrador da caixa.

Uma revisão não altera as preferências de habilitação. Remoção/desativação remota
impede a seleção sem apagar a escolha administrativa anterior. Um modelo local
arquivado na API não é recriado pela consulta.

O seletor indica a origem local. A prévia inclui HEADER/BODY/FOOTER quando houver.
O BODY suporta variáveis posicionais consecutivas; o frontend envia nome, idioma,
parâmetros e `connect_api_version`, não uma definição substituta. O backend verifica
os valores, a revisão e a correspondência da prévia com o catálogo da própria
caixa tanto na criação quanto no caminho de envio validado existente.

A API é a autoridade final: renderiza seu cadastro persistido e envia como texto
pela mesma instância. Revisão diferente retorna conflito; não há fallback livre,
troca de credencial nem repetição HTTP automática em caso de erro. Um retorno sem
ID não é tratado como confirmação. Em timeout, a entrega pode ter ocorrido;
verifique antes de reenviar. Isso não constitui garantia de exactly-once.

## Uso

1. Na Connect|API: Instâncias → instância → Modelos de mensagem. Confirme `hello`
   e crie/edite outros modelos locais.
2. No HUB: Configurações → Caixas de entrada → caixa → Configuração da Connect|API
   → Reconciliar agora. A notificação distingue catálogo vazio de importação.
3. Em Templates de abertura, mantenha `hello` ou libere outros modelos reais.
4. Em Nova conversa, selecione o modelo, preencha as variáveis e confira a prévia.

Não há alteração em conversas existentes, contatos, fluxo de chamadas,
armazenamento S3/MinIO ou templates oficiais. Modelos locais de mídia/botões não
fazem parte desta primeira entrega e não são apresentados como disponíveis.

## Testes

```bash
ruby scripts/test-connect-api-opening-templates.rb
node --test scripts/test-connect-api-opening-templates.mjs
ruby scripts/test-connect-api-local-templates.rb
node --test scripts/test-connect-api-local-templates.mjs
bundle exec rspec spec/services/whatsapp/providers/connect_api_local_templates_spec.rb
```

Os scripts novos não usam Rails, WhatsApp ou HTTP real; exercitam classes/helper e
método de envio reais com dependências de hospedagem/rede simuladas. O spec Rails
separado utiliza o ambiente de teste normal e HTTP interceptado. O workflow HUB
Quality executa ambos os níveis, sem retirar os testes existentes.
