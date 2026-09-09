# HUB — Validação da limpeza de referências e base de dependências

Data: 2026-09-08

## Escopo implementado

Esta entrega aplica a limpeza diretamente no HUB, sem camada de compatibilidade com instalações anteriores. O pressuposto desta versão é implantação nova, com dados novos.

### Cadeia de dependências

- Removidas dependências Ruby instaladas diretamente de repositórios Git de fornecedor.
- `Gemfile` não contém `git:`/GitHub como fonte de gems.
- Removidos aliases npm que mascaravam pacotes externos com nomes `@hub/*`.
- Criados pacotes locais próprios:
  - `@hub/utils`
  - `@hub/editor`
  - `@hub/command-palette`
- Criada política de senha própria do HUB.
- Criado conversor HTML → texto próprio usando Nokogiri já presente no ecossistema Rails da aplicação.
- Retirado o adapter Azure Storage legado que dependia de fork Git específico. Microsoft OAuth para e-mail permanece independente.

### Namespace próprio

Os identificadores operacionais antigos foram substituídos diretamente pelo namespace HUB, sem leitura/fallback do formato anterior. Entre os contratos alterados estão:

- cookie/query de conversa → `hub_conversation`;
- cookie de sessão → `hub_d_session_info`;
- cookies de usuário → `hub_user_*`;
- IndexedDB → `hub-store-*` / `hub-idb-names`;
- layout de teclado → `hub_keyboard_layout`;
- DOM do widget → `hub-widget-*` / `hub-bubble-*`;
- help center → `hub-article-content` / `hub-hc-toc`;
- origem Slack → `hub-origin-*`;
- redimensionamento de imagem → `hub_image_height`;
- modo API-only → `HUB_API_ONLY_SERVER`.

Busca final encontrou **zero referências operacionais** ao namespace/brand histórico e **zero identificadores runtime com prefixos antigos**. Existe uma única ocorrência remanescente no arquivo `LICENSE`, mantida exclusivamente como aviso jurídico da árvore histórica atual; ela não participa de build, runtime, UI ou dependências.

## Imagens-base imutáveis

Versão de base: `1.1.0`.

```text
ghcr.io/wkarts/argws-connect-hub-build-base:1.1.0
ghcr.io/wkarts/argws-connect-hub-deps-base:1.1.0
ghcr.io/wkarts/argws-connect-hub-runtime-base:1.1.0
```

### Build base

Toolchain de compilação e bibliotecas nativas.

### Dependency base

Pré-instala todas as gems e dependências JavaScript do HUB. O build comum da aplicação não executa `bundle install` nem `yarn install`.

A definição imutável leva em conta:

- `docker/base/VERSION`;
- `docker/base/deps/Dockerfile`;
- `Gemfile` / `Gemfile.lock`;
- campos de dependência do `package.json`;
- `yarn.lock`;
- `packages/**`.

### Runtime base

Mantém somente runtime Ruby e bibliotecas necessárias à execução. Git/toolchain não fazem parte da imagem final.

## CI/release

- PR continua validando fonte sem construir imagem descartável.
- `develop` aguarda `deps-base` + `runtime-base` e constrói a imagem de aplicação apenas uma vez.
- release resolve SemVer e executa preflight de tag antes do build caro.
- jobs que criam commit/tag configuram identidade Git local explicitamente.
- build e criação de tag/release continuam separados, permitindo reexecutar publicação da tag sem reconstruir a imagem.
- workflow de bases usa tags imutáveis e falha se uma definição mudar sem incremento de `docker/base/VERSION`.

## Serviços de deployment verificados estruturalmente

Produção HUB:

```text
migrate-connec-hub
rails-connec-hub
sidekiq-connec-hub
postgres-connec-hub
redis-connec-hub
```

Development HUB usa os mesmos papéis com `-develop`.

Connect|API embutida em produção:

```text
connect-api-hub
docs-connect-api-hub
postgres-connect-api-hub
redis-connect-api-hub
rabbitmq-connect-api-hub
minio-connect-api-hub
nats-connect-api-hub
zookeeper-connect-api-hub
kafka-connect-api-hub
```

Development usa os equivalentes com `-develop`.

Nos quatro Compose oficiais, todos os `container_name` conferem exatamente com seus respectivos nomes de service.

## Validações executadas nesta entrega

- `scripts/audit-hub.sh`: **OK**.
- Sintaxe Ruby: **1.128 arquivos OK**.
- Sintaxe Node nos scripts/pacotes próprios: **OK**.
- Sintaxe shell: **OK**.
- JSON (`package.json`, `RELEASE-MANIFEST.json`): **OK**.
- YAML de workflows + Compose: **12 arquivos OK**.
- Política de dependências/namespace via `scripts/validate-hub-ci.sh`: **OK na parte estática**.
- Root dependencies do `package.json` encontradas no `yarn.lock`: **0 seletores ausentes**.
- Dependências Git diretas no `Gemfile`: **zero**.
- Referências operacionais históricas fora do aviso legal: **zero**.

## Limite de validação deste ambiente

Este ambiente não possui Docker CLI nem acesso de rede ao RubyGems/Yarn Registry. Portanto não foi possível executar aqui:

- construção real das três imagens-base;
- `yarn install --frozen-lockfile` completo;
- `bundle install` completo;
- asset precompile dentro da imagem;
- suíte RSpec/Vitest completa.

Essas etapas devem rodar no GitHub Actions/runner de build com acesso aos registries. A validação de PR foi propositalmente mantida sem `docker build`; o build real ocorre somente após merge conforme o fluxo definido.
