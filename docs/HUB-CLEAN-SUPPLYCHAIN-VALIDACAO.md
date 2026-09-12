# HUB — validação de supply chain

A cadeia de build do HUB evita versionamento mutável e referências implícitas nos pipelines oficiais.

## Aplicação

Os publishers de `develop` e `main` usam o SHA Git como identidade do build e publicam tags específicas por revisão.

## Bases

As bases são content-addressed por SHA-256 de definição. `scripts/resolve-hub-base-refs.sh` centraliza o cálculo para impedir divergência entre o workflow que publica as bases e os workflows que as consomem.

Não existe `docker/base/VERSION`, bump SemVer de bases ou sobrescrita de uma tag imutável com outro conteúdo.

## Gates

`scripts/validate-hub-ci.sh` e `scripts/validate-release-flow.sh` validam:

- ausência dos mecanismos antigos de SemVer automático;
- ausência de `git push` automático para `main`;
- presença dos publishers de `develop` e `main` por branch/SHA;
- presença e formato das referências `def-<sha256>` das bases;
- consistência dos metadados de fonte do HUB;
- contratos de deployments, Ruby, scripts e infraestrutura existentes.
