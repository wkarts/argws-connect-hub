# Templates de abertura — HUB e Connect|API

## Uso

Em Configurações → Caixas de entrada → Configuração da Connect|API, a seção **Templates de abertura** exibe os templates reais importados daquela caixa/instância. **Reconciliar agora** mantém a reconciliação existente e sincroniza o catálogo completo antes de atualizar a interface.

Na primeira descoberta de cada nome + idioma, somente o nome exato `hello` vem habilitado. Os demais começam desabilitados. Os switches alteram uma preferência local, não o template remoto. Reconciliações seguintes preservam as escolhas, inclusive quando o ID remoto muda ou um template desaparece e reaparece. Templates ausentes permanecem no catálogo administrativo, mas não são oferecidos para envio.

**Nova conversa** usa somente a lista `opening_templates`: habilitação administrativa e disponibilidade remota precisam ser verdadeiras. Quando existe status, somente `APPROVED` é aceito, sem diferenciar maiúsculas/minúsculas. Ausência de status não é convertida artificialmente em aprovação. Mantém-se a restrição existente do seletor a componentes textuais suportados.

Não há criação automática de `hello`, texto fictício ou fallback para mensagem livre. Catálogo vazio mantém a abertura bloqueada. A seleção também é validada no backend, antes de salvar e novamente antes do envio, utilizando as preferências persistidas atuais. Falhas ou filas de uma primeira tentativa não autorizam um fallback em texto livre. Notas privadas, canais legados Meta e respostas de sessão já iniciada mantêm seu comportamento.

## Persistência e API

Reutilizam-se `channel_whatsapp.message_templates` (JSONB) e `message_templates_last_updated`, vinculados ao canal da caixa. Não há migration nem alteração destrutiva. Cada item recebe os metadados locais `hub_instance_name`, `hub_opening_enabled`, `hub_remote_present` e `hub_remote_available`. Templates de outra instância não são disponibilizados nessa caixa.

Sob `/api/v1/accounts/:account_id/inboxes/:inbox_id`:

- `GET /connect_api_templates` retorna o catálogo administrativo, `last_synced_at`, `message_templates` e `opening_templates`.
- `PATCH /connect_api_templates` recebe `name`, `language` e `enabled` estritamente booleano. Exige administrador e acesso à caixa; não cria templates. Nome não descoberto retorna 404 e booleano inválido retorna 422.

O token da instância é usado somente no backend para consultar `/graph/v14.0/:business_account_id/message_templates`. Não é serializado para o navegador. Todas as páginas são consultadas antes da atualização sob lock da linha. A operação mescla as preferências atuais sem executar novamente o provisionamento do canal. Uma resposta antiga não sobrescreve uma sincronização mais recente.

HTTP com erro, timeout, conteúdo malformado, mudança da instância durante a requisição e paginação inválida preservam o catálogo e a última sincronização bem-sucedida. Paginação aceita apenas o mesmo esquema, host, porta e caminho. Redirecionamentos estão desativados e tokens de query string são descartados. Um array vazio válido marca os registros anteriores como indisponíveis, preservando as escolhas administrativas.

## Dependência real do serviço remoto

A versão de `wkarts/ARGWS-Connect-API`, branch `develop`, consultada durante esta implementação retorna `{ data: [] }` para `WHATSAPP-BAILEYS` e `WHATSAPP-ZAPO` em `src/api/compat/meta-cloud/meta-cloud-template.service.ts` (blob `9667dbc0e7af52660eadbbca649a504d274589a9`). Nesse código, apenas `WHATSAPP-BUSINESS` consulta o serviço de templates.

Uma implantação com esse comportamento continuará sem `hello` ou outros templates após a reconciliação. Esta entrega implementa o consumo e a administração no HUB; não altera o repositório da Connect|API nem inventa um catálogo remoto. Para homologar abertura com templates, a instância precisa efetivamente fornecê-los nesse contrato.

## Ajustes visuais

Silenciar/Ativar microfone usa o mesmo arredondamento, espaçamento e dimensão-base de Encerrar, com contraste nos modos claro/escuro e carregamento interno. O script de controle de chamadas permanece idêntico à base. Desconectar mantém seu payload, exibe ação destrutiva visível, contém o carregamento e evita cliques duplicados.

## Testes

O workflow HUB Quality executa o catálogo puro (`ruby scripts/test-connect-api-opening-templates.rb`), contratos de interface (`node --test scripts/test-connect-api-opening-templates.mjs`), sintaxe Ruby, auditoria e os specs Rails de sincronização, autorização e envio. Os testes Node exercitam getters/métodos reais; não substituem compilação do bundle nem homologação visual em navegador.

Homologação: reconciliar uma instância que retorne templates reais; desabilitar `hello`, habilitar outro template e reconciliar novamente; verificar persistência, isolamento entre caixas e filtro de Nova conversa. Verificar catálogo vazio, timeout, template removido/reprovado, tentativa direta pelo backend, nota privada e respostas em sessão iniciada. Testar os botões de chamada e desconexão nos dois modos visuais.
