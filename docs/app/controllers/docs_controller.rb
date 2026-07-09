# frozen_string_literal: true

# Renders a hand-authored doc page from the Doc registry. `render_page` (from
# DocsKit::Controller) renders the Phlex page with layout: false, since the page
# composes DocsUI::Shell which IS the full HTML document.
class DocsController < ApplicationController
  def show
    doc = Doc.from_slug(params[:doc])
    view = doc&.view_class
    return head :not_found unless view

    render_page view.new
  end
end
