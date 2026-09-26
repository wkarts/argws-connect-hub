# Grupos de WhatsApp: Atendimento e Gerencial

## Escopo

Toda a administração fica em **Configurações → Caixas de entrada → caixa → Grupos**, para caixas Connect API. A guia segue a autorização nativa de edição da caixa (`InboxPolicy#update?`), tanto no frontend quanto nos GET/PATCH administrativos. Agentes comuns não configuram por URL/API; nenhum perfil paralelo foi criado. A guia continua disponível para o administrador quando grupos estão desabilitados.

Este documento descreve a implementação proposta na PR #82. A aprovação de sintaxe não equivale à homologação operacional: os testes Rails/Vue do commit e os testes reais com WhatsApp devem ser conferidos antes da release. Não houve alteração na Connect API, release/deploy ou nos artefatos da canônica 1.1.8.

## Configuração por caixa e grupo

- A habilitação mantém o parâmetro existente `ignore_group_messages`: ausente significa desabilitado. A criação da caixa começa desabilitada; toda a configuração de grupos foi concentrada na nova guia.
- Acompanhar todos ou somente grupos selecionados. No modo selecionados, novos grupos não ficam selecionados automaticamente. O administrador atualiza o catálogo por ação explícita (sem polling adicional no provedor).
- O padrão de tratamento/acesso vale para novas descobertas. Cada grupo recebe uma cópia materializada da política e pode ter uma exceção. Alterar o padrão não reclassifica grupos existentes.
- As ações em lote são limitadas a 100 grupos, exigem confirmação e verificam as versões de todas as linhas. Um conflito desfaz o lote inteiro; as notificações de alteração só são agendadas depois do commit.
- O modo Atendimento reutiliza o fluxo existente de conversas/tickets, com suas regras de atribuição, automação e métricas. O modo Gerencial tem mensagens/histórico próprios: não cria Conversation, Message de atendimento, contato artificial ou ticket oculto.
- Modos diferentes podem coexistir na mesma caixa. Escolher o modo não altera `groupsIgnore`, não recria/reconecta a instância. Somente a mudança explícita de habilitação usa a sincronização remota já existente, preservando as demais configurações da instância.

## Acesso

O padrão é herdar usuários elegíveis da caixa e manter as políticas do recurso original. O administrador conserva sua autoridade administrativa; o agente só utiliza grupos permitidos.

A seleção explícita de usuários restringe o conteúdo daquele grupo, nos dois modos. Um administrador fora da seleção ainda configura a caixa, mas não recebe mensagens/realtime/anexos do grupo até ser autorizado. Isso não representa sigilo absoluto contra quem pode editar a própria política; as alterações são auditadas.

A API deriva empresa/caixa da sessão, valida os usuários elegíveis, recusa IDs de outro escopo e não divulga a lista de autorizações em respostas operacionais. Filtros adicionais protegem conversas legadas, contatos de grupo, busca, exportação, notificações e entregas realtime. A distribuição automática só considera agentes autorizados no grupo. Remoção de associação à caixa e mudança de papel geram invalidação direcionada aos usuários afetados.

O conteúdo nunca é transmitido a um canal coletivo para ser filtrado apenas no navegador. Mensagens Gerenciais geram eventos pequenos de atualização por usuário; a interface busca o histórico pela API autorizada. Eventos de alteração de acesso limpam o conteúdo ativo antes da revalidação. Cópias já baixadas por alguém anteriormente autorizado não podem ser retiradas do dispositivo.

## Operação

A quarta guia **Grupos** permanece na mesma região de Minha / Não atribuída / Todos. Ela mostra somente grupos acessíveis, com indicação de tratamento, pesquisa, paginação, silêncio pessoal e destino correto. Não cria tickets por navegação.

Atendimento abre a conversa existente. Gerencial abre sua própria tela com mensagens, participante, arquivos, resposta, envio, status, exclusão autorizada e histórico anterior somente leitura. Mensagens de Atendimento permanecem nas filas/métricas originais; as Gerenciais ficam fora dos contadores de tickets.

O silêncio é pessoal: muda alertas, não interrompe recebimento, não altera permissões, não suspende SLA de Atendimento e não modifica o silêncio remoto do WhatsApp. A atualização usa os eventos realtime/foco/reconexão existentes; não foi acrescentado serviço permanente ou consulta periódica pesada ao catálogo.

## Identidade, dados e troca de tratamento

A identidade é empresa + caixa + JID integral `@g.us`. O participante é separado; LID não vira telefone inventado. A migração aditiva registra grupos já presentes como Atendimento, sem ligar caixas desabilitadas nem transformar mensagens existentes. As sete novas tabelas são `whatsapp_group_settings`, `whatsapp_groups`, `whatsapp_group_policy_changes`, `whatsapp_group_messages`, `whatsapp_group_deliveries`, `whatsapp_group_pending_events` e `whatsapp_group_preferences`.

Uma mensagem tem um único destino persistido no ledger por grupo/ID do provedor. Duplicatas e recibos/revogações de registros conhecidos localizam seu domínio original mesmo depois de trocar o modo. Um ledger cujo histórico foi removido continua como tombstone: replay não recria o conteúdo nem ticket. Mensagens individuais continuam no pipeline original.

A troca usa revisão otimista, trava por caixa/grupo e confirmação. Não é permitida enquanto existirem tickets não resolvidos ou envios queued/sending/uncertain. O administrador deve resolver os atendimentos e verificar/cancelar pendências explicitamente. Nenhum chamado é encerrado ou apagado como efeito silencioso do seletor.

Ativar Atendimento não abre ticket por si só. Históricos permanecem no domínio em que foram gravados, sem migração retroativa. Eventos desconhecidos datados de antes de uma troca ficam retidos, não reinterpretados pelo modo atual. A ação administrativa de importação do histórico retido (até 100 por vez) grava somente histórico Gerencial, sem tickets nem notificações de novas mensagens, independentemente do modo atual.

## Arquivos e envio

Mídia Gerencial é obtida pela credencial da instância usando os clientes existentes, com limite de 25 MB por arquivo. Não há download arbitrário de URL fornecida pelo cliente. Texto, imagem, vídeo, áudio e documento reutilizam os endpoints nativos existentes da Connect API. Cada mensagem enviada aceita um arquivo; upload e legenda têm limites validados no servidor.

Os anexos Gerenciais e anexos dos tickets de grupos são servidos por endpoint autenticado que revalida conta/caixa/grupo. URLs públicas assinadas de ActiveStorage não são usadas como autorização de leitura. O cookie de mídia é criptografado, HttpOnly, SameSite=Strict e limitado ao caminho de arquivos; referencia a sessão Devise atual e não é aceito em outras APIs. Tokens de API existentes continuam funcionando, sem troca do mecanismo de login. A resposta suporta range para áudio/vídeo, não é armazenada em cache e não executa HTML/SVG como página ativa.

O envio utiliza ID de cliente idempotente. O worker revalida modo, revisão, acesso, habilitação e identidade da instância antes de enviar. Um marcador `sending` é persistido antes do HTTP; resposta incerta não provoca reenvio automático. Após conferir no WhatsApp, o usuário pode encerrar a pendência manualmente. Isso não promete desfazer uma mensagem que o provedor eventualmente entregou. Trocar a instância impede operações remotas em registros da instância anterior.

Os logs omitem o corpo de `group_message` e argumentos sensíveis dos jobs. Diagnósticos e auditoria registram IDs, revisões e classes/status, não mensagens ou credenciais.

## Testes e homologação

Além dos testes históricos preservados, a PR inclui cenários de:

- administração nativa e isolamento entre contas/caixas; usuários selecionados e administrador não selecionado;
- coexistência Atendimento/Gerencial e ausência de Contact/Conversation/Message/Notification de atendimento na ingestão Gerencial;
- deduplicação por grupo, tombstones, recibos/revogações após transição e eventos históricos retidos;
- acesso REST, busca, realtime, anexos e URLs públicas do armazenamento;
- silêncio, envio idempotente/incerto, revogação, seleção e alteração de padrão sem reclassificação;
- interface, confirmação de troca, composição somente Gerencial e descarte de respostas atrasadas;
- chamadas com endereço de grupo sem criação de contato/ticket: conferência de voz continua não habilitada.

Antes de release: executar CI completo no commit final, preparar a migração em ambiente de teste e testar os dois modos com grupos reais, dois agentes, mídia e revogação no smartphone. Validar layout na instalação do usuário, desempenho com seu volume de grupos e o cadastro de aplicativos previamente reportado. O erro de cadastro específico não é considerado corrigido apenas por esta implementação de grupos.

Chamadas coletivas, gestão de participantes WhatsApp e edição remota de mensagens não são habilitadas por esta entrega. Não anunciar conferência a partir da capacidade de chamadas individuais simultâneas. A arquitetura própria de grupos não exige ticket para uma futura chamada Gerencial.
