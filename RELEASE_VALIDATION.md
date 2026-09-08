# HUB 3.12.8-hub.1 — validação de release

Data: 2026-09-08

## Gates concluídos

- `scripts/audit-hub.sh`: **OK**
- Sintaxe Ruby: **674 arquivos OK** com Ruby 3.3.8
- YAML de configuração/Compose: **OK**
- JSON principal + traduções WhatsApp alteradas: **OK**
- ERB do layout principal: **OK**
- Contrato Connect|API 1.0.21: **OK**
- Varredura de branding antigo em código/UI/docs próprios: **sem ocorrências**
- Varredura de telemetria/analytics/APM de terceiros no runtime/build: **sem ocorrências**
- Enterprise upstream: **não distribuído**
- Deploy: **GHCR / linux/amd64**
- Branding: **HU[B] — COMUNICAÇÃO SEM LIMITES**, PWA/favicon/Apple/Android incluídos

## Observação de build

Este ambiente de empacotamento não possui todas as gems/node_modules instaladas, então não executou o build completo de assets/Rails localmente. O Dockerfile e os workflows de CI fazem essa instalação durante o build. O primeiro build exige as imagens-base GHCR documentadas em `docs/HUB-DEPLOYMENT.md`.
