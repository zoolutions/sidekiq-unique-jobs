---
name: write-docs-page
description: "Write, add, or update a documentation page in this docs-kit site. Use when asked to document a feature, endpoint, class, or workflow, or to add or edit a page under app/views/docs/pages/. Scaffolds with `rails g docs_kit:page`, writes Markdown-first content, and runs the verification gates."
---

# Write a docs page

This is a [docs-kit](https://github.com/mhenrixon/docs-kit) site (Docs).
Every page is a `DocsUI::Page` subclass; the shell, sidebar, "On this page" TOC,
search, and the `.md` twin all come free. Your job is to scaffold a page and
write its `#content` — never hand-write HTML or daisyUI markup.

The full authoring contract is in the repo's `AGENTS.md`. This is the recipe.

## 1. Gather the subject

Identify exactly what to document (the code, endpoint, or workflow) and where it
belongs in the sidebar (the `--group`). Read the relevant source first — do not
invent behavior. If the subject is an HTTP endpoint, prefer `DocsUI::RequestExample`
/ `DocsUI::FieldTable`; if it's a Ruby API, prefer `DocsUI::PropTable`. If the
site has `c.openapi` set (an OpenAPI 3.x spec), a single `operation "operationId"`
renders the whole endpoint (badge + tables + request tabs + response) from the
spec — no hand-restatement; reach for it before hand-authoring.

## 2. Scaffold (one command)

```bash
rails g docs_kit:page "Page Title" --group=Guide
```

This writes `app/views/docs/pages/<slug>.rb` **and** injects the required
`page "…"` registry line into `app/models/doc.rb`. Overrides: `--slug`, `--view`,
`--eyebrow`, `--registry`. If it reports a legacy `entries [...]` registry, add
the printed line by hand.

## 3. Write `#content` — Markdown first

- Set `title`, `eyebrow`, and a one-sentence `lead`.
- One `DocsUI::Section("…")` per part of the page — **Sections own structure and
  the TOC.** Never use a Markdown `##` for page structure.
- Prose is `md <<~'MD' … MD` — a **single-quoted** heredoc (no escaping, no
  interpolation; Phlex escapes author text). Markdown `###` is only for
  sub-headings inside a Section.
- Reference material: `DocsUI::PropTable`, `DocsUI::FieldTable`,
  `DocsUI::RequestExample`, `DocsUI::Code(source, filename:)`,
  `DocsUI::Callout(:note | :tip | :warning)`.
- OpenAPI-backed endpoints (when `c.openapi` is set): `operation "createInvoice"`
  renders one operation as a full endpoint reference; append prose with a block —
  `operation "createInvoice" do |op| op.md("…") end` — and filter tabs with
  `clients: %i[curl ruby]`.

```ruby
class Views::Docs::Pages::PageTitle < DocsUI::Page
  title "Page Title"
  eyebrow "Guide"

  def lead = "One sentence describing the page."

  def content
    DocsUI::Section("Overview", description: "What this covers.") do
      md <<~'MD'
        Prose as **Markdown**. Fenced ```ruby``` blocks highlight; `inline code`,
        lists, links, and GFM tables all render styled.
      MD
    end
  end
end
```

## 4. Self-review against the checklist

- [ ] The `page "…"` registry line exists (the generator adds it).
- [ ] Structure is `DocsUI::Section`s, not Markdown `##` headings.
- [ ] Prose uses `md <<~'MD'` (single-quoted); no `html_safe`, no `raw`.
- [ ] No hand-written HTML/daisyUI markup, no per-feature Stimulus controller.
- [ ] Reads correctly with JavaScript off (the server renders it fully).
- [ ] Any new theme is in both `c.themes` and the Tailwind `@plugin` block.
- [ ] No inline `rubocop:disable` to force layout.

## 5. Run the gates

```bash
bundle exec rspec && bundle exec rubocop
bun run build:css   # only if you added classes the CSS must scan
```

Then render locally (`bin/dev`, open `/docs/<slug>`) and confirm it reads well.
For depth on any idiom, read the live [Authoring pages](/docs/authoring) doc.
