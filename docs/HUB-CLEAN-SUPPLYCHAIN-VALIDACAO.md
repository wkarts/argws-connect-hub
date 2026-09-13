# HUB — validação de supply chain

A cadeia de build do HUB separa claramente a versão SemVer da aplicação da identidade imutável das imagens-base.

## Aplicação

A `develop` declara a próxima SemVer nos metadados da fonte, mas sua imagem GHCR permanece `:develop`.

A `main` publica releases versionados com aliases `X.Y.Z`, `X.Y`, `X` e `latest`, além da tag Git `vX.Y.Z` e do GitHub Release correspondente. Uma referência `sha-<sha-completo>` pode existir adicionalmente para auditoria.

Nenhum pipeline calcula bump ou reescreve os arquivos de versão.

## Bases

As bases são content-addressed por SHA-256 de definição. `scripts/resolve-hub-base-refs.sh` centraliza o cálculo para impedir divergência entre o workflow que publica as bases e os workflows que as consomem.

Não existe `docker/base/VERSION`, bump SemVer de bases ou sobrescrita de uma tag `def-<sha256>` com outro conteúdo.

## Gates

`scripts/validate-hub-ci.sh` e `scripts/validate-release-flow.sh` validam:

- ausência de mecanismos de bump SemVer automático;
- sincronismo de `VERSION`, `package.json` e `RELEASE-MANIFEST.json`;
- preservação de `ghcr.io/wkarts/argws-connect-hub:develop` no canal de desenvolvimento;
- presença dos aliases SemVer obrigatórios no release de `main`;
- criação de tag Git e GitHub Release;
- ausência de `git push` automático para branches;
- presença e formato das referências `def-<sha256>` das bases;
- contratos de deployments, Ruby, scripts e infraestrutura existentes.
