# Aplicação direta na branch develop

Este pacote contém o projeto HUB completo, não um overlay.

Para substituir a árvore da branch `develop`, preserve somente o diretório `.git` do seu clone local e copie o conteúdo deste pacote sobre a raiz. Depois:

```bash
git checkout develop
git pull --ff-only
git add -A
bash scripts/audit-hub.sh
git commit -m "chore(privacy): complete HUB source without third-party telemetry"
git push origin develop
```

Não copie uma pasta `.git` de outro local. Este ZIP não inclui histórico Git.
