# Grupos de WhatsApp por caixa de entrada

O suporte é opt-in por caixa Connect API. Ausência de configuração significa **desabilitado**, inclusive em caixas existentes. A opção fica na criação/edição da própria caixa; não altera outras caixas ou a autenticação via token. Somente administradores com a autorização existente da caixa podem configurá-la.

Ao alterar a opção, o HUB consulta as configurações atuais da instância, preserva os campos de chamadas, leitura e histórico e modifica apenas `groupsIgnore`, verificando o resultado. Instâncias vinculadas externamente usam sua chave de instância. Resposta incompleta ou falta de confirmação gera erro, sem sobrescrever silenciosamente opções desconhecidas. Essa ação não reconecta nem recria a instância, não faz alterações no repositório da Connect API e não cria polling adicional. Se a comunicação interromper entre a escrita remota e a confirmação, consultar novamente e repetir a alteração é seguro/idempotente; as duas aplicações não têm transação distribuída.

## Interface

A quarta guia **Grupos** aparece somente quando há caixa habilitada e acessível no contexto atual. Uma caixa individual desabilitada não exibe a guia. As quatro opções Minha/Não atribuída/Todos/Grupos usam a mesma largura e altura da região existente; contadores grandes usam `99+`, com valor integral no hint. O fluxo restrito que esconde Todas dos agentes continua restrito e não ganha uma forma alternativa de consultar conversas.

A consulta de grupos mantém filtros de empresa, associação do atendente às caixas, caixa selecionada, equipe, marcadores, status e paginação. As três guias históricas continuam com o comportamento original: grupos também podem aparecer nelas de acordo com atribuição e permissões. Desabilitar grupos interrompe nova ingestão/envio de grupos pela caixa e retira-os da guia Grupos, **sem apagar o histórico**.

## Identidade e mensagens

Um grupo usa seu JID integral `...@g.us` como contato da conversa, sem conversão em telefone. O participante de cada mensagem é separado do grupo. Identificadores LID sem telefone não são inventados/convertidos em telefone. Nomes de participantes não substituem o nome do grupo. Texto, mídia, mensagem enviada pelo smartphone, resposta e exclusão para todos mantêm destino de grupo; eventos duplicados usam a idempotência existente. Recibos/revogações remotas de mensagens já existentes continuam sendo processados.

Reconciliação histórica e recuperação usam os jobs existentes, respeitam o opt-in e não reenviam mensagens importadas. Uma mensagem em fila é rejeitada se a caixa já tiver desabilitado grupos antes de enviá-la. Chamadas a grupos não são oferecidas nesta implementação; chamadas individuais permanecem inalteradas. Não se implementa criação de grupos, gestão de membros/administradores ou chamadas coletivas.

## Banco, carga e homologação

Há apenas um novo índice parcial concorrente em `contact_inboxes` para localizar grupos por caixa. Aplicar a migração `20260926004000` no preparo normal do banco; ela não transforma nem apaga dados. Não há dependências, containers ou workers novos. O volume de trabalho crescerá conforme o volume real de mensagens dos grupos habilitados; não prometer custo zero.

Antes da release: habilitar uma caixa de teste; receber texto/mídia de dois participantes; responder no grupo; confirmar eco único de mensagem do smartphone; testar exclusão para todos; testar atendente sem acesso; desabilitar e confirmar bloqueio sem perda de histórico. Verificar também o cadastro de um segundo aplicativo na instalação reportada, cuja falha ainda exige evidência operacional.
