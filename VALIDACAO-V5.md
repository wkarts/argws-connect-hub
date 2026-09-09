# HUB v5 — Validação da correção

Data: 2026-09-09
Base utilizada: **v2** (`HUB-1.0.0-develop-clean-base-dependencies-v2`).
As versões v3 e v4 foram deliberadamente ignoradas.

## Escopo desta v5

A v5 corrige apenas o que foi solicitado após a v2:

- preserva referências técnicas de dependências reais usadas pelo desenvolvimento/runtime;
- remove referências de produto/repositórios derivados e short-links históricos;
- não publica um link navegável para o repositório privado do HUB;
- **preserva integralmente GHCR e todos os caminhos `ghcr.io/wkarts/...`**;
- URLs operacionais do HUB deixam de depender de `hub.com`/`hub.invalid` e usam a própria instalação via `FRONTEND_URL` ou caminhos same-origin;
- cria uma fundação de documentação interna em `/docs/`;
- mantém a identidade do `github-actions[bot]` para commits/tags automáticos;
- mantém a política de licença principal do HUB separada dos avisos obrigatórios de terceiros.

## O que NÃO foi removido

Referências técnicas legítimas continuam no código quando documentam dependências ou decisões reais. Exemplos preservados:

- `https://github.com/cyu/rack-cors`
- `https://github.com/collectiveidea/audited`
- referências do Redis (`redis-rb`)
- referências do Slack (`slack-ruby-client`)
- Rails, Sidekiq, Devise, Sprockets, WebMock, Microsoft Graph e outras bibliotecas reais.

A comparação automática entre v2 e v5 confirmou **43 URLs GitHub técnicas únicas legítimas preservadas, sem remoção nem substituição**.

## GHCR

O conjunto de linhas/valores contendo `ghcr.io/` é idêntico entre v2 e v5:

- v2: 101 ocorrências
- v5: 101 ocorrências
- comparação multiset: **idêntica**

Isso inclui, entre outras:

```text
ghcr.io/wkarts/argws-connect-hub
ghcr.io/wkarts/argws-connect-hub-build-base
ghcr.io/wkarts/argws-connect-hub-deps-base
ghcr.io/wkarts/argws-connect-hub-runtime-base
ghcr.io/wkarts/hub-postgres
ghcr.io/wkarts/hub-redis
```

Nenhum GHCR foi removido ou redirecionado.

## Repositório privado

Removidos da superfície distribuída:

- link do banner de atualização para GitHub;
- labels OCI `org.opencontainers.image.source` apontando para o repositório privado;
- campo `repository` do manifesto de release;
- referências antigas aos repositórios históricos/derivados do produto.

O banner de atualização agora usa:

```text
/docs/releases/
```

A imagem no manifesto continua:

```text
ghcr.io/wkarts/argws-connect-hub
```

## URL base da instalação

Foi criado `HubDefaults`, que deriva defaults locais a partir de `FRONTEND_URL`.

Exemplo:

```env
FRONTEND_URL=https://atendimento.exemplo.com.br
MAILER_SENDER_EMAIL=
HUB_SUPPORT_EMAIL=
```

Resulta em defaults equivalentes a:

```text
HUB <no-reply@atendimento.exemplo.com.br>
support@atendimento.exemplo.com.br
```

Links de documentação são same-origin, por exemplo:

```text
/docs/
/docs/releases/
/docs/security/
```

Não existe domínio operacional `hub.invalid` nem URL operacional fixa `*.hub.com` nos caminhos distribuídos de runtime/documentação.

Fixtures e dados de teste históricos não são usados como endpoint operacional e foram deliberadamente deixados fora desta limpeza para evitar alterações desnecessárias em testes não relacionados.

## Documentação interna

Fundação criada em:

```text
public/docs/
├── index.html
├── getting-started/
├── administration/
├── integrations/
├── deployment/
├── security/
├── releases/
└── contributing-guide/
```

Ela é servida pela mesma instalação do HUB e pode evoluir depois para busca, Markdown, versionamento e edição administrativa sem depender do repositório GitHub.

## Validações executadas

- `scripts/audit-hub.sh`: **HUB AUDIT: OK**
- `scripts/validate-hub-ci.sh`: **1129 arquivos Ruby com sintaxe válida**
- shell scripts: validação OK
- JSON alterados: parse OK
- YAML alterados: parse OK
- JavaScript alterado: `node --check` OK
- `HubDefaults`: teste direto de derivação de `FRONTEND_URL` OK
- whitespace em diff v2→v5: sem erros
- hardcoded `https://github.com/wkarts/argws-connect-hub`: **0**
- referências literais a repositórios históricos derivados: **0**
- `chatwoot` fora de `THIRD_PARTY_NOTICES.md`: **0**
- `hub.com`/`hub.invalid` em runtime/documentação (excluindo testes/fixtures): **0**
- referências GHCR `ghcr.io/wkarts/...`: preservadas
- `41898282+github-actions[bot]@users.noreply.github.com`: preservado nos jobs de release

## Limites da validação local

O ambiente de validação não possui Docker Compose disponível; portanto `docker compose config`, build efetivo das imagens, instalação integral de dependências e a suíte completa RSpec/Vitest não foram executados aqui. O próprio validador registrou o skip do Compose. As validações estáticas, de sintaxe, estrutura, URLs, referências e integridade do pacote foram executadas.
