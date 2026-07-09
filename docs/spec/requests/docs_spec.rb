# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Docs site" do
  # Only pages that have a written view class are routed; unwritten registry
  # entries are skipped in the nav (see DocsKit::Registry#nav_items). We assert
  # the same set renders here, so the suite stays green while pages are authored
  # incrementally and still covers every page that actually exists.
  let(:written_docs) { Doc.all.select { |doc| doc.respond_to?(:view_class) && doc.view_class } }

  it "renders the landing page" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("sidekiq-unique-jobs")
  end

  it "has at least one written docs page" do
    expect(written_docs).not_to be_empty
  end

  it "renders every written docs page" do
    written_docs.each do |doc|
      get "/docs/#{doc.slug}"

      expect(response).to have_http_status(:ok), "expected /docs/#{doc.slug} to render, got #{response.status}"
    end
  end

  it "serves every written page as a Markdown twin" do
    written_docs.each do |doc|
      get "/docs/#{doc.slug}.md"

      expect(response).to have_http_status(:ok), "expected /docs/#{doc.slug}.md to render, got #{response.status}"
    end
  end

  it "serves the AI surfaces" do
    get "/llms.txt"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("sidekiq-unique-jobs")

    get "/llms-full.txt"
    expect(response).to have_http_status(:ok)
  end

  it "answers the healthcheck" do
    get "/up"

    expect(response).to have_http_status(:ok)
  end
end
