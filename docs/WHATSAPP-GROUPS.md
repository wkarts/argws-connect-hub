# Grupos de WhatsApp por caixa de entrada

## Estado desta preparação

**Este documento distingue o código existente da implementação a preparar.** Na referência `b4c25c63832042629fee4fe134368109fd4f7cf6`, grupos ainda usam o fluxo de `Conversation`. A guia administrativa dedicada, seleção por grupo, permissões individuais e camada Gerencial descritas abaixo **não estão implementadas nem homologadas**. Este commit é somente de documentação; não ativa recursos nem altera permissões, banco ou processamento de mensagens.

A PR #82 permanece em rascunho até implementar e validar os dois modos. Os checks aprovados na referência acima não validam funcionalidades ainda não implementadas.

## Decisão vigente: tudo se configura na caixa de entrada

O único ponto administrativo será:

**Configurações → Caixas de entrada → selecionar a caixa → Grupos.**

Não criar um painel independente de administração de grupos, novo menu global de permissões ou configuração espalhada no cadastro de agentes. A definição individual de cada grupo também fica dentro dessa guia, em linha expansível ou painel interno.

A guia operacional **Grupos**, ao lado de Minha / Não atribuída / Todos, serve para utilizar os grupos autorizados. Ela não concede acesso à configuração da caixa.

### Quem pode configurar: usar a regra que já existe

A nova guia herda integralmente a autorização de administração da caixa. Não haverá cadastro extra de quem pode administrar cada grupo.

Na base examinada:

- `app/javascript/dashboard/routes/dashboard/settings/inbox/inbox.routes.js` protege `settings_inbox_show` com `permissions: ['administrator']`.
- `app/policies/inbox_policy.rb` permite `create?`, `update?` e `destroy?` somente ao administrador; seu escopo de leitura permite caixas da conta aos administradores e caixas atribuídas aos agentes.
- `app/controllers/api/v1/accounts/inboxes_controller.rb` busca a caixa em `Current.account.inboxes`, autoriza sua leitura e também a ação correspondente. Portanto, não basta conhecer o ID de outra empresa nem esconder uma aba no frontend.

Preparar a nova configuração para reutilizar essas autorizações, e não para redefini-las:

| Operação | Administrador autorizado da empresa | Agente comum da caixa |
| --- | --- | --- |
| Abrir a guia administrativa Grupos | Sim, pela autorização existente | Não |
| Habilitar grupos e escolher quais acompanhar | Sim | Não |
| Definir Atendimento/Gerencial e acesso por grupo | Sim | Não |
| Utilizar grupos na área operacional | Conforme a política de conteúdo abaixo | Conforme a política de conteúdo abaixo |
| Silenciar alertas próprios de grupo acessível | Sim | Sim |

Os endpoints administrativos devem autorizar a operação equivalente a `InboxPolicy#update?` também em consultas administrativas, e não apenas `show?`, que pode permitir leitura operacional ao agente. Não criar um novo perfil de administrador de grupos. Se o sistema vier a permitir delegação da edição de caixas por sua política central, o módulo deverá seguir essa política sem reimplementar papéis em paralelo.

### Quem pode ler as mensagens: definição na mesma guia

Acesso à configuração e acesso ao conteúdo são decisões diferentes, mas **não são duas telas de parametrização**.

Para evitar alteração silenciosa dos contratos, o comportamento padrão proposto é **herdar o acesso já permitido pela caixa e pelo recurso**. No modo Atendimento, manter ainda as restrições existentes da conversa, inclusive papéis personalizados. Não transformar a guia Grupos em um atalho que contorne restrições de atendimento.

Na mesma guia administrativa, cada grupo poderá ser configurado como:

1. **Todos os usuários autorizados da caixa (padrão):** preserva o acesso que as políticas vigentes já permitem. Não exige adicionar o administrador repetidamente a cada grupo.
2. **Somente usuários selecionados:** restringe o conteúdo aos usuários explicitamente escolhidos, que também precisam ser elegíveis no escopo da empresa/caixa e nas políticas do recurso. A seleção não concede acesso a outra empresa ou caixa.

A seleção restrita pode incluir administradores e agentes. Se um administrador não estiver selecionado em um grupo explicitamente restrito, ele continua podendo administrar a configuração da caixa, mas a leitura operacional desse conteúdo depende da seleção. Isso não deve ser vendido como sigilo absoluto contra administradores: quem administra a política pode alterá-la. A interface precisa deixar esse efeito claro; mudanças de acesso devem ser auditadas. O padrão herdado, por outro lado, não restringe administradores que já tinham acesso.

Não acrescentar um checkbox separado "administrador pode configurar". A autorização administrativa já é a da caixa. Não utilizar o bypass de leitura de `AgentBot` para conceder acesso ao novo domínio de grupos sem política específica.

## Organização da nova guia

Adicionar a guia em `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue`, seguindo os componentes, traduções e apresentação existentes. A guia é exclusiva de caixas Connect API compatíveis, e permanece visível ao administrador quando grupos estão desabilitados, para permitir habilitá-los. Não remover ou renomear abas existentes.

### Configuração geral da caixa

- Habilitar/desabilitar grupos, preservando o opt-in existente.
- Acompanhar todos os grupos ou somente grupos selecionados.
- Tratamento padrão para novos grupos: **Atendimento** ou **Gerencial**.
- Acesso padrão para novos grupos: herdar os usuários elegíveis da caixa ou uma seleção explícita de usuários elegíveis.

Os campos de modo e acesso devem mostrar claramente o valor aplicado. Não aplicar um modo silenciosamente por erro de carregamento. Alterar o padrão de grupos novos não reclassifica grupos já configurados; alterações em lote exigem seleção, prévia e confirmação.

### Lista e configuração individual

Lista paginada com busca e atualização explícita do catálogo, sem varredura periódica pesada. Mostrar ícone/nome, acompanhamento, tratamento e acesso. Dentro da mesma guia, permitir escolher cada grupo e editar sua regra. Nome do grupo não é identificador único: usar empresa, caixa e JID integral.

Modo selecionados: grupo novo fica fora até seleção explícita. Modo todos: grupo novo recebe o padrão validado da caixa, materializado junto com a revisão aplicada; alterações posteriores do padrão não mudam essa escolha retroativamente.

Silenciamento pessoal é uma preferência operacional, acessível no grupo pelo próprio usuário. Não constitui uma segunda administração: não habilita grupos, não altera acesso e não muda Atendimento/Gerencial. Silenciar no HUB não altera remotamente o WhatsApp sem uma ação explícita. No modo Atendimento, silenciar alertas não suspende SLA, atribuição ou outras regras de atendimento.

## Duas regras de negócio por grupo

| Modo | Persistência e funcionamento | Efeitos de atendimento |
| --- | --- | --- |
| Atendimento | Preserva o pipeline existente de conversa, mensagens, anexos e chamados | Conforme as regras já configuradas: criação/reuso/reabertura, atribuição, automações e métricas |
| Gerencial | Histórico e mensagens próprios na camada de grupos, sem `Conversation` oculto | Não cria/reabre chamado, não atribui atendente e não dispara SLA, CSAT, distribuição ou automações de atendimento |

Dois grupos da mesma caixa podem usar modos diferentes. Um mesmo evento não pode criar uma mensagem nos dois domínios. A seleção Atendimento/Gerencial é local ao HUB, não modifica `groupsIgnore`, não reconecta a instância e não altera código da Connect API.

A guia operacional Grupos reúne somente grupos autorizados, com indicação discreta do modo. Atendimento abre seu recurso existente; Gerencial abre a camada própria. Apenas registros de Atendimento participam das guias e métricas de tickets conforme o contrato histórico. Exibir um grupo de Atendimento na guia Grupos não duplica conversas ou contadores.

## Preparação técnica para implementar sem quebrar contratos

### 1. Configuração e catálogo

Criar endpoints novos escopados à conta e à caixa para configuração e catálogo, reutilizando a autorização de edição da caixa. Separar a resposta administrativa, que pode conter seleção de usuários, da resposta operacional. Não acrescentar a lista completa de autorizações a payloads de inbox consumidos por todos os agentes.

Persistir o cadastro de grupo e suas regras no HUB, com chave única por caixa/JID e revisão de configuração. A identidade da conta é derivada/validada a partir da caixa, não aceita livremente do cliente. Rejeitar grupos, usuários ou IDs pertencentes a outro escopo antes da gravação. Defaults e substituições individuais devem ter uma regra de precedência única no servidor.

Não criar endpoints para gerenciar membros/administradores do grupo no WhatsApp nesta etapa. Usuários do HUB autorizados a ler não são os participantes WhatsApp.

### 2. Resolver política antes de criar atendimento

Mensagens individuais continuam no caminho atual. Para grupos, identificar JID e consultar habilitação, seleção e regra efetiva antes de criar contatos/conversas de atendimento.

Atendimento delega ao caminho já existente em `Whatsapp::IncomingConnectApiGroups`. Gerencial encaminha a entidades/serviços próprios de grupo e mensagens. Recepção Gerencial não pode chamar builders de `Conversation`, nem utilizar `Message` de atendimento como suporte oculto se isso disparar seus callbacks.

Política inválida ou indisponível não é motivo para encaminhar ao atendimento. Preservar uma possibilidade segura de reprocessamento e registrar diagnóstico sem expor conteúdo sensível; não descartar definitivamente o evento nem criar ticket como fallback.

### 3. Identidade, atualizações e deduplicação

Preservar JID integral `@g.us`, participante separado, ID do provedor e identidade LID sem converter LID em telefone. Manter registro do destino original e revisão da regra para cada mensagem, com deduplicação no escopo apropriado.

Ecos, recibos, edições e revogações localizam a mensagem original, inclusive depois da troca de modo. Não decidir o destino de uma atualização histórica apenas pelo modo atual. Recebimento, envio, mídia, resposta, encaminhamento, retries e recuperação devem obedecer a mesma resolução de política e idempotência.

Histórico desconhecido e eventos fora de ordem precisam de uma regra temporal explícita e testes. Não reaplicar cegamente a regra vigente a todo o passado, duplicar conteúdo nem abrir chamados por efeito colateral de replay.

### 4. Aplicar acesso em todas as superfícies

Resolver a leitura a partir de conta/caixa + política do recurso + seleção adicional do grupo. Revalidar envio e atribuição; a distribuição automática não pode selecionar agente impedido de ler aquele grupo.

Cobrir listas, REST, URLs diretas, busca, histórico, anexos, downloads/URLs assinadas, exportações, contadores, notificações e realtime. Não transmitir o conteúdo a um canal coletivo de conta para depois filtrá-lo apenas no navegador. Revogação deve impedir novas entregas também para sessões já abertas e tarefas enfileiradas. Não prometer retirar cópias já baixadas pelo usuário.

Manter autenticação e contratos históricos; adicionar a autorização por recurso sem exigir que consumidores mudem tokens nem alterem payloads de mensagens individuais. Alterar recursos compartilhados apenas nos pontos estritamente necessários, com regressões correspondentes.

### 5. Troca de modo e dados existentes

Mapear explicitamente para Atendimento grupos que já utilizam o comportamento anterior, sem ativar caixas desabilitadas ou converter grupos silenciosamente. Antes de qualquer migração de histórico, inventariar o que realmente existe; não presumir que a branch já foi implantada.

Troca de modo exige autorização administrativa, confirmação, revisão auditável e coordenação das operações em andamento por grupo. Ao passar para Gerencial, tratar chamados e envios pendentes explicitamente antes de concluir a transição; não apagar/encerrar chamados silenciosamente. Depois de ativada a nova revisão, trabalho antigo não pode abrir/reabrir ticket nesse grupo por atraso de fila.

Ao passar para Atendimento, gravar a opção não cria chamado por si só. O próximo evento novo elegível usa as regras históricas de criação/reuso. Históricos permanecem no domínio original, sem cópia retroativa automática; atualizações de registros antigos continuam atualizando o registro correto sem efeitos indevidos.

### 6. Disponibilização conjunta

Não mostrar um modo Gerencial selecionável enquanto sua persistência, envio, leitura e autorização não estiverem completos. Não entregar tela salvando uma regra que o backend ignore. Manter a PR em rascunho até passar a matriz abaixo e a homologação real. Não retirar testes ou enfraquecer guardas para obter CI verde.

## Matriz mínima de aceite — ainda pendente

| Cenário | Resultado exigido |
| --- | --- |
| Administrador da conta configura a caixa | Acesso autorizado pela regra nativa, sem permissão nova por grupo |
| Agente abre URL administrativa ou tenta GET/PATCH direto | Configuração negada no servidor; uso de grupos autorizados continua possível |
| Outra empresa fornece ID de caixa/grupo/usuário | Acesso negado e zero alterações |
| Acesso herdado sem restrição explícita | Mantém a autoridade e as restrições históricas aplicáveis |
| Grupo restrito a usuários selecionados | Seleção aplicada em conteúdo, APIs, anexos e realtime, sem ampliar escopos |
| Administrador fora da seleção restrita | Configura a caixa, mas não recebe conteúdo operacional até seleção explícita |
| Agente com papel personalizado em Atendimento | Guia Grupos não contorna restrições da conversa |
| Revogação com sessão aberta | Novos acessos e entregas bloqueados; preferências não concedem permissão |
| Dois grupos da mesma caixa em modos distintos | Um usa Atendimento e o outro não cria/reabre nenhum ticket |
| Recepção/envio/mídia Gerencial | Sem Conversation, atribuição, SLA, CSAT ou automação de atendimento |
| Atendimento | Mantém pipeline, automações e contadores que já se aplicavam |
| Todos/selecionados e novos grupos | Somente grupos elegíveis são processados; defaults explícitos e estáveis |
| Troca de padrão da caixa | Não reclassifica grupos existentes silenciosamente |
| Silenciamento pessoal | Sem alertas pessoais, com histórico e ingestão preservados |
| Retry, eco, histórico e revogação após troca de modo | Uma mensagem/destino original, sem ticket ou cópia indevida |
| Troca de modo com fila/ticket em andamento | Exige tratamento explícito e mantém histórico; nenhuma perda silenciosa |
| Habilitação desativada durante envio pendente | Novo envio bloqueado, sem apagar histórico |
| Interface | Mesma região das quatro guias; sem controles de chamado no modo Gerencial |
| Regressões | Mensagens individuais, chamadas existentes, autenticação e demais caixas preservadas |

## Código existente em b4c25c6 — preservar como base do Atendimento

O suporte é opt-in por caixa Connect API. Ausência de configuração significa **desabilitado**, inclusive em caixas existentes. A opção fica na criação/edição da própria caixa; não altera outras caixas ou a autenticação via token. Somente administradores com a autorização existente da caixa podem configurá-la. A preparação acima deslocará a administração completa para a nova guia, sem remover a compatibilidade do parâmetro existente.

Ao alterar a opção de habilitação, o HUB consulta as configurações atuais da instância, preserva os campos de chamadas, leitura e histórico e modifica apenas `groupsIgnore`, verificando o resultado. Instâncias vinculadas externamente usam sua chave de instância. Resposta incompleta ou falta de confirmação gera erro, sem sobrescrever silenciosamente opções desconhecidas. Essa ação não reconecta nem recria a instância, não faz alterações no repositório da Connect API e não cria polling adicional. Se a comunicação interromper entre a escrita remota e a confirmação, consultar novamente e repetir a alteração é seguro/idempotente; as duas aplicações não têm transação distribuída.

### Interface existente

A quarta guia **Grupos** aparece somente quando há caixa habilitada e acessível no contexto atual. Uma caixa individual desabilitada não exibe a guia. As quatro opções Minha/Não atribuída/Todos/Grupos usam a mesma largura e altura da região existente; contadores grandes usam `99+`, com valor integral no hint. O fluxo restrito que esconde Todas dos agentes continua restrito e não ganha uma forma alternativa de consultar conversas.

A consulta de grupos mantém filtros de empresa, associação do atendente às caixas, caixa selecionada, equipe, marcadores, status e paginação. As três guias históricas continuam com o comportamento original: grupos de Atendimento também podem aparecer nelas de acordo com atribuição e permissões. Desabilitar grupos interrompe nova ingestão/envio de grupos pela caixa e retira-os da guia Grupos, **sem apagar o histórico**.

### Identidade e mensagens existentes

Um grupo de Atendimento usa seu JID integral `...@g.us` como contato da conversa, sem conversão em telefone. O participante de cada mensagem é separado do grupo. Identificadores LID sem telefone não são inventados/convertidos em telefone. Nomes de participantes não substituem o nome do grupo. Texto, mídia, mensagem enviada pelo smartphone, resposta e exclusão para todos mantêm destino de grupo; eventos duplicados usam a idempotência existente. Recibos/revogações remotas de mensagens já existentes continuam sendo processados.

Reconciliação histórica e recuperação usam os jobs existentes, respeitam o opt-in e não reenviam mensagens importadas. Uma mensagem em fila é rejeitada se a caixa já tiver desabilitado grupos antes de enviá-la. Chamadas a grupos não são oferecidas nesta implementação; chamadas individuais permanecem inalteradas. Não se implementa criação de grupos, gestão de membros/administradores ou chamadas coletivas.

### Banco, carga e homologação da base

Há apenas um novo índice parcial concorrente em `contact_inboxes` na implementação de b4c25c6 para localizar grupos por caixa. A migração `20260926004000` não transforma nem apaga dados. A futura camada Gerencial precisará de migrações aditivas próprias, ainda não incluídas. Não há dependências, containers ou workers novos nesta preparação. O volume de trabalho crescerá conforme o volume real de mensagens dos grupos habilitados; não prometer custo zero.

Antes da release, além da nova matriz: habilitar uma caixa de teste; receber texto/mídia de dois participantes; responder; confirmar eco único de mensagem do smartphone; testar exclusão para todos; testar atendente sem acesso; desabilitar e confirmar bloqueio sem perda de histórico. Verificar também o cadastro de um segundo aplicativo na instalação reportada, cuja falha ainda exige evidência operacional.

## Fora desta preparação

Chamadas de voz em grupo continuam como evolução futura, com capacidade própria a verificar/homologar no provedor; chamadas simultâneas individuais não comprovam conferência. Não vincular uma futura chamada Gerencial a um ticket. Não modificar o repositório da Connect API nesta tarefa.

Preservar restauração dos aplicativos, sidebar/hints e demais correções anteriores. A canônica 1.1.8 e suas guardas de retenção/republicação não são alteradas por esta preparação. Não executar merge, deploy, release ou limpeza de armazenamento como efeito desta documentação.
