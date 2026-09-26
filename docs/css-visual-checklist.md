# Verificação visual do CSS

O refactor de setembro de 2026 partiu de `site/assets/story.css` (25 177 bytes)
e das mesmas 29 páginas HTML geradas: página inicial, metodologia, índice e
24 páginas de freguesia. A comparação de screenshots deve usar um servidor HTTP
local, porque as páginas referem `/assets/story.css` por caminho absoluto.

1. Execute `npm run site:build` e sirva `_site/` localmente.
2. Compare a página inicial, `metodologia.html`, `freguesias/` e uma página de
   freguesia (por exemplo, `freguesias/lumiar/`) em 1440 × 900 e 390 × 844.
3. Reveja também 850 px e uma largura intermédia, nomes de freguesia longos,
   métricas grandes e pequenas e a apresentação sem citações.
4. Confirme foco visível por teclado, o salto para o conteúdo e a preferência
   por movimento reduzido.
5. Execute `npm run site:check`,
   `ruby scripts/audit_publication.rb --artifact _site` e `git diff --check`.

Mantenha mudanças de aparência em commits separados de refactors da estrutura
CSS, para que a comparação visual continue útil.
