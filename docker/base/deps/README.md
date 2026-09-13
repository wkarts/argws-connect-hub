# HUB Dependency Base

A imagem `argws-connect-hub-deps-base` é content-addressed e só deve ser reconstruída quando a definição real de dependências mudar.

Entradas que alteram a identidade da dependency base:

- `docker/base/deps/Dockerfile`
- `Gemfile` / `Gemfile.lock`
- `package.json` (somente campos de dependências/resoluções/engines usados pelo resolver)
- `yarn.lock`
- pacotes locais em `packages/**`
- definição exata da `build-base`

Mudanças somente de versão da aplicação não alteram o hash da dependency base. O workflow pode ser acionado para verificar o estado, mas a publicação é pulada quando a tag imutável `def-<sha256>` já existe e possui o label de definição esperado.

Antes de publicar dependências JavaScript, `package.json` e `yarn.lock` devem estar sincronizados para que `yarn install --frozen-lockfile` seja determinístico.
