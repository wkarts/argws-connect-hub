# 🅷🆄🅱

HUB é uma plataforma privada de comunicação, atendimento e colaboração multicanal.

## Canais

- **WhatsApp — Connect|API**: QR Code, código de pareamento, mensagens, mídia, replies, reactions e chamadas quando o provider oferecer suporte.
- **E-mail — IMAP/SMTP**: recebimento e envio por servidores padrão; o servidor IMAP continua sendo a autoridade física da caixa postal.
- Outros canais podem ser habilitados por integrações próprias do HUB.

## Privacidade

O HUB não envia telemetria de produto para serviços externos por padrão.

## Connect|API

Configure no servidor HUB:

```env
CONNECT_API_BASE_URL=https://api.connect.exemplo.com
CONNECT_API_AUTH_TOKEN=troque-pelo-token-global-da-connect-api
```

O token global permanece no backend. Sessões de mídia usam tickets temporários quando o recurso está disponível na Connect|API.

## Dependências

O build do HUB não instala gems diretamente de repositórios Git e não depende de pacotes de namespaces externos específicos do produto.

Pacotes específicos do produto são mantidos no próprio repositório:

```text
packages/hub-utils
packages/hub-editor
packages/hub-command-palette
```

As dependências Ruby e JavaScript ficam pré-instaladas na imagem imutável `argws-connect-hub-deps-base`, reconstruída somente quando manifests/locks/pacotes locais mudam.

## Namespace interno

Cookies, parâmetros, IDs DOM, caches e chaves internas usam prefixos `hub_` / `hub-`.

Não existe camada de compatibilidade com os identificadores antigos: novas instalações começam com dados novos.

## Containers

Consulte `docs/HUB-DEPLOYMENT.md`.

A aplicação usa três bases independentes de release da aplicação:

```text
argws-connect-hub-build-base
argws-connect-hub-deps-base
argws-connect-hub-runtime-base
```

`develop` e releases utilizam a mesma família de bases imutáveis.

## Licenciamento

HUB é um produto privado mantido pela ARGWS. Código e ativos próprios do HUB
são proprietários. Componentes de terceiros eventualmente presentes continuam
sujeitos exclusivamente às respectivas licenças, documentadas separadamente em
`THIRD_PARTY_NOTICES.md`.
