# HUB — autenticação GHCR no deployment

O HUB pode usar pacotes privados no GitHub Container Registry sem colocar credenciais dentro dos containers.

Cada `.env` de deployment deve conter:

```env
GHCR_REGISTRY=ghcr.io
GHCR_USERNAME=wkarts
GHCR_TOKEN=SEU_TOKEN_COM_READ_PACKAGES
```

O arquivo `.env` já é ignorado pelo Git e não deve ser commitado.

## Configurar todos os deployments de uma vez

A partir da raiz do repositório, execute:

```bash
bash ./scripts/configure-ghcr-auth.sh
```

O token será solicitado com entrada oculta. O script:

1. cria o `.env` a partir de `.env.example` somente quando o `.env` ainda não existir;
2. grava `GHCR_REGISTRY`, `GHCR_USERNAME` e `GHCR_TOKEN` nos quatro deployments;
3. autentica o Docker do host no GHCR;
4. valida as imagens GHCR resolvidas por cada Compose;
5. se encontrar o container `dockge`, autentica também o cliente Docker usado pelo Dockge.

Também é possível fornecer o token somente para o processo atual, sem colocá-lo na linha de comando:

```bash
export GHCR_TOKEN='SEU_TOKEN'
bash ./scripts/configure-ghcr-auth.sh
unset GHCR_TOKEN
```

Se o container do Dockge tiver outro nome:

```bash
DOCKGE_CONTAINER=nome-do-container bash ./scripts/configure-ghcr-auth.sh
```

## Deploy pelo host

A partir da raiz do repositório:

```bash
bash ./scripts/deploy-hub.sh deployment/production/standalone
```

Development:

```bash
bash ./scripts/deploy-hub.sh deployment/development/standalone
```

O script executa nesta ordem:

1. lê `GHCR_REGISTRY`, `GHCR_USERNAME` e `GHCR_TOKEN` do `.env`;
2. executa `docker login` com `--password-stdin`;
3. valida todas as imagens `ghcr.io` resolvidas pelo Compose;
4. executa `docker compose pull`;
5. executa `docker compose up -d`.

Para apenas baixar:

```bash
bash ./scripts/deploy-hub.sh deployment/production/standalone pull
```

## Dockge

Quando o Compose é iniciado pelo Dockge, autentique também o ambiente do próprio Dockge antes do primeiro pull privado:

```bash
bash ./scripts/ghcr-login-dockge.sh deployment/production/standalone/.env dockge
```

Development:

```bash
bash ./scripts/ghcr-login-dockge.sh deployment/development/standalone/.env dockge
```

Depois use normalmente **Atualizar/Iniciar** no Dockge.

Se o container do Dockge for recriado e perder o arquivo de credenciais do Docker, execute novamente o comando acima ou `configure-ghcr-auth.sh`.

## Segurança

- O token não é definido em `environment:` dos serviços.
- O token não é incluído na imagem.
- O token não é enviado para Rails, Sidekiq, PostgreSQL, Redis ou Connect|API.
- O token é usado somente pelo cliente Docker responsável pelos pulls.
- Os `.env` reais permanecem fora do Git.
- Prefira um token dedicado somente para leitura dos pacotes necessários.
