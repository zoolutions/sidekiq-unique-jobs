# AGENTS.md

Guidance for AI coding agents working in this repository. `AGENTS.md` is the
cross-tool convention (Claude Code, Cursor, Copilot, Aider, …); Claude Code also
reads it through the bundled `write-docs-page` skill. Edit freely — a
`docs_kit:install` re-run only touches the delimited block below.

<!-- BEGIN docs-kit -->
## Writing docs pages (docs-kit)

Docs is a [docs-kit](https://github.com/zoolutions/docs-kit) site: a
Phlex/daisyUI chrome where **every page is a `DocsUI::Page` subclass** and the
sidebar, TOC, search, and Markdown twin come free. To document something, you
scaffold a page, then write its `#content`. Never hand-write HTML or daisyUI
markup — compose the kit's `DocsUI::` helpers.

### 1. Scaffold the page (one command)

```bash
rails g docs_kit:page "Getting Started" --group=Guide
```

That writes `app/views/docs/pages/getting_started.rb` **and** injects
`page "Getting Started", group: "Guide"` into the `Doc` registry — so the page is
routed and in the sidebar the moment you fill in `#content`. Overrides:
`--slug=auth`, `--view=OauthGuide`, `--eyebrow="Advanced"`, `--registry=Guide`.
Re-running is idempotent.

> The registry line is **required** — a page with no `page "…"` line in
> `app/models/doc.rb` is not routed and not in the nav. The generator adds it;
> if you hand-write a page, add the line yourself.

### 2. Write `#content` — Markdown first

Prose is `md` with a **single-quoted** heredoc (`<<~'MD'`) so `#{…}` stays
literal (Phlex escapes author text — never `html_safe` or interpolate):

```ruby
class Views::Docs::Pages::Guide < DocsUI::Page
  title "Guide"
  eyebrow "Getting started"

  def lead = "One sentence under the page title."

  def content
    DocsUI::Section("First steps", description: "What this covers.") do
      md <<~'MD'
        Prose as **Markdown** — lists, `inline code`, links, GFM tables, and
        fenced ```ruby``` blocks all render styled. Use Markdown `###` only for
        sub-headings *inside* a Section.
      MD

      DocsUI::Code(<<~RUBY, filename: "config/routes.rb")
        Rails.application.routes.draw { mount DocsKit::Engine, at: "/docs" }
      RUBY
    end
  end
end
```

### The authoring contract

- **`DocsUI::Section` owns page structure and the "On this page" TOC.** One
  Section per part of the page; each heading becomes a TOC entry. **Never** use a
  Markdown `##` for page structure — only for sub-headings inside a Section.
- **The primary argument is positional; modifiers are keywords.**
  `Section("Title", description:)`, `Code(source, filename:)`,
  `Header("Title", eyebrow:)`.
- **Wrappers that take no positional arg use lowercase page helpers** so a block
  needs no parens: `md <<~'MD' … MD`, `prose { … }`, `example { |ex| … }`,
  `operation "operationId"`. (A bare `DocsUI::Prose do` is a Ruby SyntaxError; the
  helpers sidestep it.)
- **Reference material has dedicated helpers** — reach for these before prose:
  `DocsUI::PropTable`, `DocsUI::FieldTable`, `DocsUI::RequestExample`,
  `DocsUI::Callout(:note | :tip | :warning)`.
- **OpenAPI-backed endpoints** (when `c.openapi` is set): `operation "createInvoice"`
  renders a whole endpoint from the spec — badge, field/error tables, request tabs,
  response — no hand-restatement. Append prose with a block; filter tabs with
  `clients:`.

### Invariants — do not break

- **The registry line is required** (see above) — no line, no page.
- **The page must work with JavaScript off.** The server renders it fully;
  the one `docs-nav` controller only *enhances*. Never require JS to read a page.
- **Themes offered must exist in the CSS build** — `c.themes` in
  `config/initializers/docs_kit.rb` must match the `@plugin "daisyui" { themes: … }`
  block in `app/assets/stylesheets/application.tailwind.css`. Don't add one
  without the other.
- **No inline `rubocop:disable`** to force layout — write idiomatic Ruby the
  site's cops accept.

### 3. Verify before you finish

```bash
bundle exec rspec && bundle exec rubocop   # tests + lint must pass
bun run build:css                          # if you added classes the CSS scans
```

Then render the page locally (`bin/dev`, open `/docs/<slug>`) and confirm it
reads correctly — with JavaScript off, too.

**Depth:** the live [Authoring pages](/docs/authoring) doc is the full,
always-current version of this contract. When in doubt, read it.
<!-- END docs-kit -->
