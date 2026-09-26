# Aplicativos por empresa — HUB

## Operação

O catálogo começa vazio. Um administrador cadastra os aplicativos em
**Configurações → Aplicativos**. Não há seeds, aplicativos sugeridos ou integrações
pré-configuradas. Nome, ícone de linha ou imagem PNG/JPEG/WebP (até 1 MB), endereço
HTTPS, ordem, disponibilidade, abertura e permissões pertencem à empresa atual.
Administradores podem administrar todos os aplicativos da própria empresa;
agentes veem somente os aplicativos habilitados para eles.

O botão Aplicativos na sidebar abre uma segunda faixa estreita. Selecionar um
aplicativo interno recolhe o seletor e acrescenta um ícone à área de guias abertas.
Cada guia tem sua própria instância de iframe, fora do router-view. Alternar para
conversas, contatos, configurações ou outra guia apenas oculta a anterior, sem
recriar o iframe nem trocar seu endereço. Uma aplicação já aberta é selecionada
sem nova chamada de rede. Uma mudança apenas no nome/ícone não reinicia a guia.

Recarregar e fechar exigem confirmação. Fechar remove a instância, mas não o
cadastro. Sair da conta ou trocar de empresa limpa as instâncias e o estado local.
As guias pertencem à sessão de cada usuário, e não a todos os usuários da empresa.
Atualizar/fechar o navegador destrói a sessão visual; não há restauração de
formulários, nem armazenamento de páginas ou senhas no localStorage/sessionStorage.

Os modos de abertura são **Dentro do HUB** e **Aba externa**. No segundo modo,
o navegador abre o destino com noopener/noreferrer; não é uma guia que o HUB
possa inspecionar ou controlar. Aplicativos não são carregados antes de abertos.
Enquanto há guias abertas, a lista de permissões é revalidada a cada 60 segundos
e ao recuperar foco. Erros de conectividade não desmontam as guias; revogação,
remoção e mudanças na configuração de integração encerram as instâncias afetadas.

## Autenticação

### Login do próprio aplicativo

A interface do destino autentica normalmente, incluindo MFA, CAPTCHA e fluxos de
identidade que o sistema já oferece. O HUB não lê campos nem captura senhas do
iframe. Sessões existentes são administradas pelo próprio destino/navegador.

### POST configurado e autorizado

Disponível apenas na abertura interna. O administrador informa a URL HTTPS de
login (na mesma origem do aplicativo) e os nomes dos campos de usuário e senha.
Este modo atende exclusivamente destinos preparados para receber esse POST e
estabelecer uma sessão web. Não tenta adivinhar formulários, contornar CSRF,
resolver CAPTCHA/MFA, chamar uma API esperando que seu token crie uma sessão web,
injetar scripts ou remover cabeçalhos de segurança do destino.

Na primeira abertura, cada usuário informa suas credenciais explicitamente no
painel **Meu login**. O nome e o domínio do destino ficam visíveis. Usar as
credenciais próprias do sistema de destino. O HUB não reutiliza automaticamente
sua senha, nem modifica seu login, 2FA ou tokens de API.

Permitir salvar credenciais e permitir login automático são políticas separadas,
ambas desativadas inicialmente. O usuário também precisa marcar explicitamente
**Salvar minhas credenciais** e **Entrar automaticamente**. Sem consentimento,
o POST pode ocorrer, mas a senha não é persistida. No painel Meu login, o dono
pode reutilizar ou excluir suas credenciais. Uma configuração administrativa nunca
exibe nem compartilha a senha de outro usuário.

O servidor valida usuário, empresa, acesso, revisão da integração e política a
cada lançamento. O frontend cria um formulário temporário, envia somente os
campos configurados para o iframe e remove/limpa os campos em seguida. Não usa
a instância axios autenticada do HUB para chamar o destino externo.

O cofre usa AES-256-GCM e uma chave derivada do SECRET_KEY_BASE já existente,
com contexto criptográfico por aplicativo e vínculo usuário/empresa. Não há nova
variável de ambiente nem segredo compartilhado em URL. Manter a chave existente
na atualização é necessário; sua substituição invalida as credenciais anteriores.
O endpoint GET de credenciais retorna apenas metadados do próprio usuário.
Somente o POST de lançamento interativo pode devolver temporariamente a senha ao
próprio cliente para o envio ao destino. Tokens estáticos da API não acessam esse
fluxo. Respostas não são cacheáveis; parâmetros de credenciais são filtrados dos
logs. Mudança de URL/modo/campos revoga o cofre; desativar armazenamento o apaga;
desativar login automático limpa a preferência automática.

## Limites de incorporação e execução

O destino deve autorizar o domínio do HUB em suas regras de frame. O HUB não
remove X-Frame-Options, CSP/frame-ancestors nem proteções de cookies. Não há proxy
que burle restrições, nem teste automático capaz de comprovar todo login externo.
Use Aba externa quando o destino não for compatível. O diagnóstico não afirma
que um evento load comprova sucesso de autenticação.

O sandbox permite os recursos necessários a aplicações web, mas não navegação
arbitrária do topo. Câmera, microfone, geolocalização e pagamentos ficam negados.
Não é permitido incorporar a própria origem do HUB.

Manter o iframe montado evita reinício causado pela navegação do HUB; **não impede
que o navegador/sistema operacional limite, congele ou descarte páginas**. Não
usar uma guia como garantia de execução de tarefas críticas em segundo plano.
Cookies de aplicativos na mesma origem seguem as regras do navegador: guias não
são perfis isolados, e trocar de empresa no HUB não encerra automaticamente a
sessão do sistema externo. O destino também precisa tratar seu contexto empresarial.

## Atualização e verificação

Aplicar `bundle exec rails db:migrate` (ou o preparo de banco previsto no deploy)
antes de disponibilizar a nova interface. A migração cria workspace_apps e
workspace_app_credentials, com chaves estrangeiras e índice único do cofre por
aplicativo/vínculo. Não modifica tabelas de mensagens nem o broker/Connect API.
O deploy deve usar os assets compilados desta mesma versão. Nenhum compose/env
novo é necessário. Em rollback, não reverter as tabelas antes de retirar o código
novo de execução; reverter a migração apaga o catálogo/cofre deste recurso.

Testes incluídos:

```sh
node --test scripts/test-workspace-apps.mjs scripts/test-workspace-presentation.mjs
ruby scripts/test-workspace-diagnostics.rb
node --experimental-vm-modules --test scripts/test-workspace-state.mjs
node --experimental-vm-modules scripts/check-workspace-javascript.mjs
node scripts/check-workspace-vue.cjs
yarn test app/javascript/dashboard/components/workspace/specs
bundle exec rspec spec/models/workspace_app_spec.rb spec/models/workspace_app_credential_spec.rb spec/requests/workspace_apps_spec.rb spec/requests/workspace_diagnostics_spec.rb
```

O workflow HUB Quality executa contratos, compilação Vue, testes de ciclo de vida
de iframes e testes Rails de permissões/cofre. Homologar também no navegador real
com cada destino: login inicial, retorno às conversas, volta à mesma página,
fechamento, múltiplas guias, isolamento de empresa e limitações de cookies.

## Avatar de contatos

O formulário usa um único preview dentro do componente de upload. Trocar/apagar
a imagem continuam disponíveis, e clicar na foto mantém a ampliação. Foram
retirados a lupa e o texto de instrução, sem duplicar a imagem. Outros usos do
uploader preservam sua miniatura original pelo fallback do slot.

## Refinamento Web/PWA: camadas, controles e ícones

Continua exclusivamente Web/PWA. Não adiciona Electron, WebView2, navegador
remoto, extensão, serviço, worker ou dependência. Os ícones permanecem em botões
40 × 40 px, como os itens nativos. Imagens enviadas são apresentadas em 28 × 28 px
com proporção e transparência preservadas; o arquivo original não é regravado.
Hints usam a diretiva nativa do HUB, em `body`, com atraso de 180 ms, sem capturar
o ponteiro. O seletor e as guias abertas continuam sem nomes permanentes.

A área das aplicações fica no plano de conteúdo (camada 10), abaixo do seletor
(20), menu de perfil (30), hints/contexto (40) e diálogos globais. Suas bordas são
medidas pela sidebar real, incluindo zoom, RTL e banners. O modal de confirmação
é irmão do plano de conteúdo, não filho de uma camada que o aprisionaria.

A barra tem 38 px, texto de 12 px e ícone de 28 px. Desafixada por padrão,
aparece pelo puxador no topo e por foco do teclado; o botão Fixar mantém a barra
visível. A preferência é somente um booleano local, por empresa/usuário, sem
senhas ou páginas. A ocultação não altera a chave do iframe. O menu de botão
direito/Shift+F10 oferece fechar, fechar outros, recarregar e abrir externamente;
fechamento/recarga passam pela confirmação existente de perda de alterações.

As listas têm rolagem funcional com scrollbar invisível, roda do mouse, toque,
setas discretas e teclado (cima/baixo, início/fim, PageUp/PageDown). O rodapé com
perfil e notificações permanece fora da lista rolável.

## Voltar e avançar sem sair do HUB

O HUB não chama `window.history.back()`/`forward()` para controlar uma guia:
isso navegaria no histórico do HUB. Um iframe de outra origem não permite ler
ou controlar diretamente seu histórico. Os botões ficam desabilitados, com
hint explicativo, até o destino anunciar a integração opcional de navegação.

O responsável pelo **aplicativo de destino**, sem alterar seus mecanismos de
login, pode adicionar em todas as páginas do aplicativo:

```html
<script src="https://SEU-HUB/workspace-navigation-bridge.js"
        data-hub-origin="https://SEU-HUB" defer></script>
```

Use a origem exata do HUB, sem barra final. O destino deve autorizar o script na
sua CSP, ou hospedar uma cópia própria desse arquivo. O script é opcional e não
é injetado, nem pré-configura aplicativos no catálogo. Ele usa a Navigation API
quando disponível, com histórico limitado ao contexto e à origem do destino;
em navegadores antigos sem essa API os botões permanecem indisponíveis. Não
transmite URL de navegação, conteúdo de página, credenciais ou tokens. Mensagens
validam origem exata, janela emissora, tipos e nonce por carregamento. O botão
Voltar ao HUB continua funcionando mesmo sem o script, sem fechar a aplicação.

## Diagnosticar um destino que não abre

O botão **Diagnosticar carregamento** abre orientações dentro do HUB, sem remover
o iframe. Uma consulta autenticada e explícita (`POST .../workspace_apps/:id/diagnose`)
usa apenas a URL cadastrada daquele aplicativo, após validar empresa, usuário e
permissão. Não aceita URL/headers/origem fornecidos no corpo. Tokens estáticos de
API não disparam essa consulta. O resultado é reaproveitado por 45 segundos.

O servidor faz somente HEAD HTTPS, sem cookies, autorização, login ou corpo da
página; limite total de 8 segundos, até 3 redirecionamentos e nenhuma repetição
automática. Valida todos os IPs retornados pelo DNS e fixa o IP da conexão,
mantendo verificação TLS/SNI do hostname. Recusa IPs privados, locais, reservados,
IPv4 mapeado e transições IPv6; cada redirecionamento é validado novamente.
Não usa proxy de ambiente nem ignora certificados. Essa restrição protege o HUB
contra SSRF e não impede que o navegador do usuário abra um serviço interno.

O painel mostra a origem efetiva do navegador, a origem configurada no servidor,
status/etapas HTTP, X-Frame-Options e frame-ancestors observados. Classifica DNS,
TLS, timeout e conexão recusada **na consulta do servidor**, sem inventar um erro
do navegador. CSP Report-Only não é tratada como bloqueio; CSPs impostas são
cumulativas e frame-ancestors prevalece sobre X-Frame-Options em navegadores que
suportam CSP. Sintaxe não interpretável fica inconclusiva. URLs do relatório
omitem query e fragmento; senhas e tokens de sessão do HUB nunca são incluídos.

A resposta sem autenticação pode diferir da página autenticada no navegador;
HEAD pode ser recusado por um site que aceita GET. Ausência de bloqueio não é
sucesso confirmado. O evento load não comprova renderização e erros de iframe
nem sempre são expostos. Eventos `securitypolicyviolation` do HUB são apresentados
apenas quando identificam este destino e uma diretiva imposta frame-src/child-src.
Para o erro exato do navegador, o painel orienta usar F12 → Console/Rede.

A correção de frame-ancestors deve ser feita pelo responsável do destino,
autorizando a origem exata do HUB na política existente (não substituir toda a
CSP, liberar `*`, desabilitar segurança ou falsificar User-Agent). Também devem
ser verificados proxy/CDN, certificados, cookies e regras do login. Este patch
não modifica nenhum sistema externo, incluindo a aplicação mostrada no exemplo.

## Restauração após recarregar ou reabrir o HUB

O navegador armazena somente IDs dos aplicativos, a revisão da integração e o ID da guia ativa, separados por empresa e usuário. Não são armazenados URLs, senhas, tokens ou dados internos das páginas. O catálogo autorizado é consultado novamente antes de reconstruir os iframes. Aplicativos excluídos, desativados, sem permissão, com destino alterado ou convertidos em links externos não são reabertos automaticamente. Fechar explicitamente uma guia remove-a da restauração. Retornar às conversas apenas a oculta. Falhas temporárias de rede não apagam a lista de restauração; o evento `online` ou foco permite tentar novamente.

Reabrir restaura uma **nova página** no endereço cadastrado, não a memória do iframe que foi encerrado. A sessão de login depende dos cookies válidos do aplicativo e das regras do navegador, ou do login POST previamente autorizado. Formulários não salvos, downloads locais e JavaScript do iframe não continuam executando depois que o navegador é fechado. Processos que pertencem ao servidor do aplicativo podem continuar lá. O HUB não assume controle desses processos e não instala navegador remoto, worker ou serviço adicional. Limpar o armazenamento do navegador remove a lista de restauração. O catálogo é revalidado também ao trocar de empresa/usuário.

## Falhas no cadastro e preparação de release

O formulário preserva `error`/`message`, status HTTP e ID de requisição devolvidos pelo servidor. Criação e alteração passam a emitir diagnóstico seguro `workspace.write_finished`/`workspace.write_failed` com status/classe e nomes dos campos inválidos, **sem seus valores**. Erros de gravação ficam no registrador existente. Falhas bloqueadas antes de chegar ao controller (proxy, autenticação, rede) devem ser correlacionadas pelo status e ID da requisição no navegador.

O diagnóstico antigo fornecido não continha as tentativas recentes de cadastro. Os testes de criação JSON/multipart e de segundo aplicativo passam, mas isso **não comprova que a falha específica da instalação foi resolvida**. Confirmar uma criação real antes da próxima release de produção.
