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
Use Aba externa quando o destino não for compatível. O aviso na guia não afirma
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
node --test scripts/test-workspace-apps.mjs
node --experimental-vm-modules --test scripts/test-workspace-state.mjs
node --experimental-vm-modules scripts/check-workspace-javascript.mjs
node scripts/check-workspace-vue.cjs
yarn test app/javascript/dashboard/components/workspace/specs/workspaceApps.spec.js
bundle exec rspec spec/models/workspace_app_spec.rb spec/models/workspace_app_credential_spec.rb spec/requests/workspace_apps_spec.rb
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
