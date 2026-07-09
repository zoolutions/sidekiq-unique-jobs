# frozen_string_literal: true

# In-memory registry of the reference docs. One line per page — slug and view
# derive from the title (both overridable), and the sidebar nav derives from
# this registry with zero extra code (see config/initializers/docs_kit.rb's
# `nav_registries`). Add a page with `rails g docs_kit:page "Title" --group=…`,
# which appends the `page` line here and writes the class under
# app/views/docs/pages/.
#
# Unwritten pages are silently skipped by docs-kit, so this registry doubles as
# an authoring burn-down list: every line here without a matching page class is a
# page still to write.
#
# Uses DocsKit::Registry for the shared all/from_slug/grouped/nav_items API.
class Doc
  extend DocsKit::Registry
  path_prefix    "/docs"
  view_namespace "Views::Docs::Pages"

  # Getting started
  page "Overview", group: "Getting started"
  page "Installation", group: "Getting started"
  page "Quick start", group: "Getting started"

  # Concepts — how it works
  page "How locking works", group: "Concepts"
  page "Lock lifecycle", group: "Concepts"
  page "Choosing a lock type", group: "Concepts"
  page "Conflict resolution", group: "Concepts"
  page "TTL and timeouts", group: "Concepts"
  page "ReliableFetch", group: "Concepts"
  page "Orphaned locks and recovery", group: "Concepts"
  page "Observability", group: "Concepts"

  # Use cases — one purpose, one complete worker
  page "Debounce duplicate enqueues", group: "Use cases"
  page "Process exactly once", group: "Use cases"
  page "One per period", group: "Use cases"
  page "Serialize per resource", group: "Use cases"
  page "Enqueue once, run serialized", group: "Use cases"
  page "Only the latest matters", group: "Use cases"
  page "Retry conflicts later", group: "Use cases"
  page "Bounded concurrency", group: "Use cases"
  page "Custom uniqueness arguments", group: "Use cases"

  # Testing
  page "Testing unique jobs", group: "Testing"

  # Migrate
  page "Upgrading to v9", group: "Migrate"

  # Reference
  page "Configuration reference", group: "Reference"
  page "Worker options", group: "Reference"
  page "Reflections", group: "Reference"
  page "Web UI", group: "Reference"
end
