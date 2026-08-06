# jekylldown — draft de design (v0.0.1)

> **Ideia em uma frase:** fazer para o **Jekyll** o que o `blogdown` do Yihui Xie fez
> para o Hugo — um pacote R que cria, serve, knita (`.Rmd` → `.md`) e builda sites
> Jekyll, destravando o ecossistema de temas do Jekyll (em especial o **al-folio**)
> para usuários de R.

- **Autor:** Allan V. C. Quadros
- **Data:** 2026-08-03
- **Status:** protótipo implementado (2026-08-03) — itens 1–5 do §5 prontos e
  testados; falta o item 6 (migração de uma cópia do site real). Toolchain de
  teste: Ruby 4.0.6 (conda-forge via micromamba) + jekyll 4.4.1 isolados em
  `tools::R_user_dir("jekylldown", "data")` — validando a rota micromamba do
  §3.2 sem tocar no sistema.
- **Caso de uso âncora:** migrar https://allanvc.github.io/ (hoje blogdown/Hugo,
  tema hugo-researcher) para o tema al-folio mantendo um fluxo de trabalho em R.

---

## 1. Motivação

1. O al-folio (Jekyll) é hoje o tema acadêmico de referência — publicações geradas
   a partir de BibTeX, news, CV, teaching como dados estruturados. O Hugo não tem
   equivalente à altura.
2. O GitHub Pages builda Jekyll **nativamente** — para temas simples nem GitHub
   Actions é necessário; o al-folio traz Actions prontas. Isso elimina o fluxo
   atual de dois repositórios (fonte + `public/` aninhado) do blogdown.
3. Não existe hoje um pacote "com acabamento" para isso. O que existe são
   esqueletos do próprio Yihui (ver §3) sem interface de pacote, sem `new_site()`,
   sem gestão de dependências, sem documentação.
4. Subproduto pessoal: pacote publicável (CRAN) com caso de uso concreto — este
   próprio site como demo.

## 2. O que as buscas mostraram (feitas em 2026-08-03)

### 2.1 Pacotes R sobre Ruby — correção importante

A hipótese era que os pacotes de mapas do **Kyle Walker** (tidycensus, tigris,
mapgl) rodassem sobre Ruby. **Não é o caso**: são pacotes R puros sobre APIs do
Census Bureau + `sf`/GDAL (tidycensus importa httr, sf, dplyr, tigris, etc. —
nada de Ruby). O mapgl usa Mapbox/MapLibre (JavaScript).

- https://walker-data.com/tidycensus/
- https://cran.r-project.org/package=tidycensus
- https://www.rdocumentation.org/packages/tigris/versions/2.1

Mais amplo: a busca por pacotes CRAN que embrulham gems Ruby **não encontrou
precedente estabelecido**. Não existe um "reticulate do Ruby". O mecanismo padrão
do R para dependências externas é o campo `SystemRequirements` do DESCRIPTION
(texto livre), catalogado em:

- https://github.com/rstudio/r-system-requirements
- https://cran.r-project.org/doc/FAQ/R-exts.html (Writing R Extensions)

**Implicação de design:** o jekylldown não deve tentar uma ponte R↔Ruby em nível
de linguagem. O acoplamento correto é por **linha de comando** (chamar os
executáveis `jekyll`/`bundle` via `processx`/`system2`), exatamente como o
blogdown chama o binário do Hugo. `SystemRequirements: Ruby (>= 3.0), bundler`.

### 2.2 Quarto — famoso, mas não onipresente

Quarto é o sucessor oficial do R Markdown e há migração real de blogdown → Quarto
(existe até o pacote {bd2q} para converter). Mas:

- O próprio time do Quarto diz que ele **não substitui** o blogdown/Hugo — é um
  gerador próprio, com ecossistema de temas próprio (e sem nada como o al-folio).
- A adoção para *blogs/sites pessoais* é crescente mas não dominante; blogdown
  segue válido e citado como opção.

Fontes: https://github.com/quarto-dev/quarto-cli/discussions/2099 ·
https://www.r-bloggers.com/2023/05/moving-from-blogdown-to-quarto/ ·
https://www.rostrum.blog/posts/2023-05-07-bd2q/ · https://quarto.org/docs/blog/

**Implicação:** existe um nicho real — quem quer temas Jekyll (al-folio à frente)
não é atendido nem pelo blogdown nem pelo Quarto.

### 2.3 Prior art direto — o caminho já está meio pavimentado

O próprio Yihui deixou os esqueletos; nenhum virou pacote:

- **`servr::jekyll()`** — serve um site Jekyll com live reload, re-knitando `.Rmd`
  quando o fonte é mais novo que o output. Por padrão procura `.Rmd` na raiz, em
  `_source/` e `_posts/`; compila `_source/*.Rmd` → `_posts/*.md`.
  https://www.rdocumentation.org/packages/servr/versions/0.5/topics/jekyll
- **`yihui/knitr-jekyll`** — repositório-exemplo do arranjo acima.
  https://github.com/yihui/knitr-jekyll (fork: https://github.com/brendan-R/knitr-jekyll)
- **`yihui/blogdown-jekyll`** — "Automatically knit R Markdown documents, build
  them with Jekyll, and serve the website with servr locally".
  https://github.com/yihui/blogdown-jekyll
- Receitas da comunidade para deploy no GitHub Pages:
  https://selbydavid.com/2017/06/16/rmarkdown-jekyll/ ·
  https://www.r-bloggers.com/2017/06/deploying-an-r-markdown-jekyll-site-to-github-pages/

**Implicação:** o jekylldown v0.0.1 é, essencialmente, "pegar `servr::jekyll()` +
knitr-jekyll e dar acabamento de pacote": scaffolding de site, gestão de posts,
verificação de dependências, e integração com temas remotos (al-folio).

## 3. O desafio central assumido: `install_jekyll()` multiplataforma

**Decisão de projeto (2026-08-03): vamos entregar um `install_jekyll()` que
funciona em Linux, macOS e Windows.** Hugo é um binário único e foi por isso que
o Yihui o escolheu — mas o mesmo Yihui depois provou que o problema "instalar
uma toolchain inteira a partir do R" é solúvel: o **tinytex** instala uma
distribuição TeX completa, multiplataforma, sem privilégios de admin. Ruby +
Jekyll é um problema *menor* que TeX. Precedentes que mostram o caminho:

- `tinytex::install_tinytex()` — distribuição TeX inteira, user-level, 3 SOs.
- `reticulate::install_miniconda()` — provisiona um Python completo isolado.
- `blogdown::install_hugo()` — o caso fácil, mas o padrão de UX a copiar.

### 3.1 Princípios

1. **Nunca tocar no sistema.** Tudo vai para `tools::R_user_dir("jekylldown",
   "data")`: Ruby provisionado (quando necessário) e um `GEM_HOME` isolado.
   Sem `sudo`, sem `gem install` global, sem conflito com Ruby do usuário.
   Desinstalar = apagar um diretório.
2. **Fast path primeiro.** Se já existe Ruby ≥ 3.0 utilizável no PATH (caso
   desta máquina), só criamos o `GEM_HOME` isolado e instalamos as gems nele.
   Provisionar Ruby é o fallback, não a regra.
3. **Toda invocação de jekyll/bundler passa pelo pacote**, que injeta
   `GEM_HOME`/`GEM_PATH`/`PATH` corretos — o usuário nunca precisa configurar
   ambiente.

### 3.2 Provisionamento de Ruby por plataforma (quando não há Ruby)

| SO | Estratégia primária | Observações |
|---|---|---|
| **Windows** | Baixar o **RubyInstaller+Devkit em 7z portátil** e extrair no user dir | Sem admin; o Devkit traz MSYS2/gcc, então gems nativas compilam; ffi/eventmachine também publicam gems pré-compiladas mingw |
| **macOS** | **portable-ruby do Homebrew** (tarball relocável, arm64 + x86_64, GitHub Releases) | É o Ruby com que o próprio brew se bootstrapa — battle-tested; compilar gems nativas usa CommandLineTools |
| **Linux** | portable-ruby (x86_64/glibc) ou **micromamba + ruby do conda-forge** | conda-forge também fornece compiladores se faltarem no sistema |

Rota unificada alternativa (a avaliar no protótipo): **micromamba nas três
plataformas** — um único binário estático que cria um env isolado com
`ruby` do conda-forge; um só código de provisionamento para os 3 SOs, ao custo
de downloads maiores.

### 3.3 O problema das gems nativas — mapeado, não mítico

As dependências do Jekyll que compilam C são poucas e conhecidas:
`eventmachine` + `http_parser.rb` (via `em-websocket`, usados só pelo
`jekyll serve` nativo) e `ffi` (via `listen`, só em Linux). O resto é Ruby puro,
e `sass-embedded` já vem **pré-compilado por plataforma**. Ou seja:

- **Windows:** RubyInstaller Devkit compila; e as gems críticas publicam
  binários mingw pré-compilados.
- **macOS/Linux:** exigem toolchain C (CommandLineTools / gcc+make+headers) —
  `install_jekyll()` detecta e, na rota conda, pode provisionar o compilador.
- **Plano B elegante:** o live reload do jekylldown é do **servr (lado R)** —
  se `eventmachine` falhar em alguma máquina, `jekyll build` + servr cobre o
  fluxo inteiro sem o `jekyll serve` nativo.

### 3.4 Redes de segurança (complementos, não substitutos)

- `check()` continua existindo como sitrep de diagnóstico.
- **Modo "sem Ruby local"**: o knit `.Rmd` → `.md` só precisa de R; o build pode
  ficar no GitHub Actions (o al-folio já traz o workflow). Preview local é
  opcional para quem só edita conteúdo.
- Docker documentado como último recurso (o al-folio publica imagem oficial).

## 4. Arquitetura proposta

```
usuário R
   │
   ├─ new_site(theme = "alshedivat/al-folio")   # clona/copia o tema, cria _source/
   ├─ new_post("meu-post", rmd = TRUE)          # cria _source/YYYY-MM-DD-slug.Rmd
   │
   ├─ build_site()                              # 1) knita _source/*.Rmd → _posts/*.md
   │                                            #    (knitr, base.dir/fig.path ajustados)
   │                                            # 2) opcional: jekyll build (se Ruby local)
   │
   ├─ serve_site()                              # servr::jekyll() embrulhado:
   │                                            # live reload + re-knit automático
   └─ check()                                   # diagnóstico ruby/bundler/jekyll/gems
```

### 4.1 Convenções de arquivo (herdadas do knitr-jekyll)

| Onde | O quê |
|---|---|
| `_source/*.Rmd` | posts em R Markdown (fonte, ignorado pelo Jekyll via `exclude:`) |
| `_posts/*.md` | output do knit — **artefato**, nunca editar à mão |
| `assets/img/posts/<slug>/` | figuras geradas pelo knitr (`fig.path` apontado para cá) |
| `_config.yml` | config do Jekyll — o pacote lê/escreve chaves via {yaml} |

### 4.2 Decisões técnicas

- **Knit:** `knitr::knit()` direto (não `rmarkdown::render()`) — queremos `.md`
  com front matter preservado, não HTML. Hooks do knitr para: prefixar caminhos
  de figura com `{{ site.baseurl }}`, cercar output em fences compatíveis com
  kramdown/rouge.
- **Processos externos:** {processx} (não `system()`) para `jekyll build`/`serve`
  — captura de stderr para mensagens de erro legíveis.
- **Front matter:** {yaml} para ler/escrever; validar campos exigidos pelo tema
  (`layout: post`, `date`, etc.).
- **Sem ponte Ruby em runtime.** Ruby é `SystemRequirements`, chamado por CLI.
- **Dependências R (alvo mínimo):** knitr, servr, yaml, processx, xfun, fs, cli.

### 4.3 API pública v0.0.1

```r
jekylldown::new_site(dir, theme = c("minima", "al-folio"), ...)
jekylldown::new_post(title, date = Sys.Date(), rmd = TRUE, ...)
jekylldown::build_site(local_jekyll = NULL)   # NULL = auto-detecta Ruby
jekylldown::serve_site(...)                   # wrapper de servr::jekyll()
jekylldown::stop_server()
jekylldown::check()                           # sitrep de dependências
jekylldown::bundle_install(dir)               # gems do Gemfile do tema (al-folio)
jekylldown::migrate_hugo(from, to, theme)     # blogdown/Hugo -> Jekyll (best effort)
jekylldown::knit_post(input, output)          # um post; usado pelo build.R do servr
```

Nomes espelham o blogdown de propósito — custo de aprendizado ~zero para quem
vem de lá (eu, no caso).

## 5. Escopo do protótipo v0.0.1

**Meta:** do zero a um site al-folio com um post `.Rmd` knitado, servido
localmente e publicável no GitHub Pages.

1. Esqueleto de pacote (DESCRIPTION, licença MIT, roxygen2).
2. `check()` — diagnóstico de ruby/bundler/jekyll.
3. `new_site()` com tema `minima` (gem padrão, sem submódulos — caminho feliz)
   e `al-folio` (clone do repo template).
4. Pipeline de knit `_source/*.Rmd` → `_posts/*.md` com figuras em
   `assets/img/posts/` (portar hooks do knitr-jekyll).
5. `serve_site()`/`build_site()` sobre servr/processx.
6. Testar de ponta a ponta com **uma cópia do conteúdo do meu site** como caso
   de uso real (fica em pasta separada — nunca mexer no
   `~/Documents/r-projects/my_webpage`, que segue sendo o site em produção).

7. *(adicionado em 2026-08-03)* `migrate_hugo()` — migração best-effort
   blogdown/Hugo → Jekyll: front matter YAML/TOML, renomeação de posts,
   bundles, `static/`, shortcodes `figure`/`youtube`, atributos Pandoc;
   relatório do que fica manual. Validada com cópia do site real.
8. *(adicionado em 2026-08-04)* `bundle_install()` + `bundle exec jekyll`
   automático quando o site tem `Gemfile.lock` (necessário para os plugins
   do al-folio); README.Rmd e vignette de migração.

**Fora do escopo v0.0.1:** `install_jekyll()` automático (a rota micromamba
foi validada manualmente — ver §6), Windows, CRAN (isso é v0.1.0+).

## 6. Ambiente desta máquina (verificado em 2026-08-03)

- Ruby 3.0.2 em `/usr/bin/ruby`, `gem` disponível; **jekyll e bundler ainda não
  instalados** (`gem install bundler jekyll` ou via apt).
- R 4.4.1.
- O site atual (blogdown/Hugo) permanece intocado em
  `~/Documents/r-projects/my_webpage` até o jekylldown provar que funciona.

## 7. Adendo — estado em 0.0.7 (2026-08-06)

O escopo original (§1-5) foi cumprido e ultrapassado. Entregas além do
plano inicial, na ordem (ver NEWS.md para o detalhe por versão):

1. **Migração sem passos manuais** (0.0.2): socials extraídos das páginas
   do Hugo por regex determinística; gem jupyter removido; scrub profundo
   do tooling upstream; `publications = "bib"` virou default.
2. **Tabelas e Quarto** (0.0.3): IAL `{: .table}` automático (kramdown);
   posts `.qmd` via CLI do Quarto, adaptados às mesmas convenções.
3. **Pandoc e serve novo** (0.0.4): `knit_method: pandoc` para citações/
   footnotes; `serve_site()` reescrito sobre `servr::httw()` (vigia
   Rmd/qmd/md/config/estilos); `install_quarto()` no toolchain isolado.
4. **Customização declarativa** (0.0.6): quatro camadas — variáveis CSS
   do tema, fontes, elementos semânticos (camada frágil, documentada
   como tal), CSS gerenciado — todas em blocos marcados idempotentes.
5. **Multi-tema** (0.0.7): al-folio, Chirpy, Minimal Mistakes e minima
   como alvos de primeira classe de `new_site()`, das camadas de estilo
   (Chirpy: variáveis CSS; MM: skins via `set_theme_skin()`) e de
   `migrate_hugo()` (cada tema recebe páginas/navegação/avatar/socials
   na sua própria convenção). Decisão baseada em pesquisa de adoção
   (stars/forks no GitHub, downloads no RubyGems).

**Continua fora do escopo:** `install_jekyll()` automático, Windows,
CRAN.
