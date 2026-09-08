# Dependências externas preservadas

O produto e a interface são **HUB/🅷🆄🅱**. Para evitar quebrar o build nesta release, seis dependências de terceiros continuam referenciando coordenadas históricas do projeto de origem apenas nos manifests/lockfiles:

- npm: `ninja-keys`, `prosemirror-schema` e `utils` (consumidos internamente pelo namespace `@hub/*`)
- Ruby: forks de `azure-storage-ruby`, `devise-secure_password` e `html2text_ruby`

Esses nomes **não são branding do produto nem aparecem na interface**. Atribuições/licenças permanecem em `THIRD_PARTY_NOTICES.md` e `LICENSE` conforme necessário.

Para independência completa de supply-chain, publique forks equivalentes sob sua organização e então troque apenas as coordenadas dos manifests, sem alterar os contratos internos do HUB.
