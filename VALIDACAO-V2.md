# HUB — validação da revisão v2

## Motivo da revisão

Revisão do pacote `HUB-1.0.0-develop-clean-base-dependencies` após comparação de diretórios.

### Política de senha

A ausência dos arquivos antigos:

- `config/initializers/secure_password.rb`
- `config/locales/secure_password.en.yml`
- `config/locales/secure_password.es.yml`
- `config/locales/secure_password.pt_BR.yml`

é intencional. A dependência/extension antiga foi substituída pela implementação própria do HUB:

- `config/initializers/hub_password_policy.rb`
- `app/models/concerns/hub_password_policy.rb`
- `config/locales/hub_password_policy.en.yml`
- `config/locales/hub_password_policy.es.yml`
- `config/locales/hub_password_policy.pt_BR.yml`

`User` inclui `HubPasswordPolicy`. A política mantém os quatro requisitos usados pelo projeto: maiúscula, minúscula, número e caractere especial, configuráveis por `HUB_PASSWORD_REQUIRED_*`.

### `public/icons`

O source package anterior não continha arquivos Git rastreados em `public/icons`; o diretório observado localmente provavelmente era vazio/gerado. Para evitar que a pasta desapareça em ZIP/Git, esta revisão inclui `public/icons/.keep`. Nenhum asset funcional foi deliberadamente excluído desta pasta.

### Recursos remotos

Foram removidas dependências de runtime em URLs fictícias/legadas `*.hub.com` e `chwt.app`.

- testimonials: agora `/assets/data/testimonials.json` local;
- documentação/help: `/help/` local;
- HMAC/OpenAI/help de features: rotas locais;
- termos e privacidade: páginas locais com possibilidade de override pela configuração global;
- exemplos/test fixtures que usavam `hub.com`: usam domínio reservado `.invalid` ou asset local;
- atualização do HUB: aponta para o repositório próprio `wkarts/argws-connect-hub`.

O audit do HUB agora bloqueia a reintrodução de `hub.com`/`chwt.app` no runtime distribuído.

### Licenciamento

O `LICENSE` principal agora descreve somente o código/ativos próprios da ARGWS como proprietários e não apresenta HUB como upstream/distribuição de outro produto.

Avisos de terceiros permanecem em `THIRD_PARTY_NOTICES.md`. Isso é necessário enquanto a árvore atual ainda contiver porções de terceiros sujeitas às respectivas licenças. Esses avisos não definem branding, propriedade ou identidade do HUB.

O `package.json` raiz usa `"license": "UNLICENSED"`.

## Validações executadas

- `HUB AUDIT: OK`;
- Ruby syntax OK nos arquivos alterados de runtime;
- política própria `HubPasswordPolicy` presente e extensão antiga ausente;
- JSON alterado parseado com sucesso;
- YAML alterado parseado com sucesso;
- JavaScript alterado principal validado por `node --check`;
- zero URL `*.hub.com` ou `chwt.app` no runtime do HUB (fora de avisos/licenças e fixtures excluídas pelo gate);
- `public/icons/.keep` presente;
- testimonials/help/terms/privacy locais presentes.

## Limitação

Não houve build Docker nem execução integral de RSpec/Vitest neste ambiente. O pacote preserva a arquitetura de CI criada anteriormente para que esses testes/builds sejam executados no GitHub Actions.
