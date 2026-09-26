# Versões canônicas: retenção permanente

`1.1.8` permanece canônica e nunca deve ser reconstruída, retaggeada ou excluída pelos fluxos do HUB. Outras versões podem ser adicionadas futuramente; mudar a canônica atual não remove a retenção das anteriores. `latest` é um alias de publicação, não a definição de versão canônica.

Referências verificadas em 25/09/2026:

- Tag Git existente: `v1.1.8` (preservado o prefixo histórico).
- Objeto da tag: `115e0f5d985fa05851ea6915d7e98ceb398ce6ce`.
- Commit de origem: `580e870343960f9702c2e681ead1c76b9715deee`.
- GitHub Release: ID `388604100`.
- Imagem: `ghcr.io/wkarts/argws-connect-hub:1.1.8`.
- Digest original: `sha256:dd0aa7fe967b9e6ff9ad9aeb33b092932cd10f2287fde9b7e798f6863bf61dac`.

## Proteções do código

O registro `config/canonical-releases.json` é cumulativo. O validador mantém uma referência obrigatória à 1.1.8; o CI compara com a base da PR para impedir remoção/substituição das canônicas anteriores. O publicador recusa reutilizar uma versão canônica, verifica tag/commit/release e digest antes de nova publicação e não altera seus artefatos. A limpeza do GHCR preserva qualquer versão que tenha a tag ou digest protegido, independentemente de posição na lista, idade, aliases ou novas versões. Manifestos OCI filhos e atestações sem tag continuam preservados. Registro inválido/ausente bloqueia a limpeza de imagens.

Testes locais da limpeza usam um `gh` falso e fixtures: nenhum artefato real é excluído durante os testes. A checagem remota é somente leitura. Se um artefato canônico desaparecer, o fluxo falha e informa o problema, **não tenta reconstruí-lo silenciosamente**.

## Limites administrativos

A consulta à release existente retornou `immutable: false`. Este trabalho não exclui/republica a release antiga nem afirma ter habilitado a imutabilidade nativa do GitHub. As proteções acima cobrem os pipelines versionados do projeto; uma ação manual de administrador, outro workflow sem essas guardas ou a exclusão do repositório/pacote ainda são riscos administrativos. Configurar adicionalmente regras de tag bloqueando alteração/exclusão de `v1.1.8` sem bypass de bots e limitar permissões de exclusão do pacote. Essas regras exigem acesso administrativo não exposto pelas ações de escrita disponíveis nesta sessão. Manter backup independente dos artefatos é recomendável.

A liberação da próxima release permanece condicionada à aprovação do CI, build de produção e homologação dos aplicativos/grupos. Esta implementação não muda a versão atual nem publica uma release automaticamente na branch de desenvolvimento.
