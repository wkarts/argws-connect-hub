# HUB infrastructure images

O HUB mantém espelhos controlados de PostgreSQL e Redis no próprio GHCR:

- `ghcr.io/wkarts/hub-postgres:16-alpine`
- `ghcr.io/wkarts/hub-postgres:16`
- `ghcr.io/wkarts/hub-redis:7-alpine`
- `ghcr.io/wkarts/hub-redis:7`

A publicação é feita por `.github/workflows/ghcr-sync-infrastructure.yml`. O workflow não atualiza as imagens por agenda; uma atualização do upstream só é incorporada quando o workflow for executado manualmente ou quando a própria definição do workflow for alterada na `develop`.

As stacks continuam configuráveis por `HUB_POSTGRES_IMAGE` e `HUB_REDIS_IMAGE`, com os espelhos acima como padrão.

## Visibilidade no GHCR

O GitHub Container Registry cria novos pacotes com visibilidade privada por padrão. Para que PostgreSQL e Redis possam ser baixados por uma instalação nova sem login no GHCR, os pacotes `hub-postgres` e `hub-redis` devem ser definidos como **Public** uma única vez em Package settings após a primeira publicação.

Essa visibilidade se aplica somente às imagens de infraestrutura. A imagem principal `ghcr.io/wkarts/argws-connect-hub` pode continuar privada e exigir autenticação do host de implantação.
