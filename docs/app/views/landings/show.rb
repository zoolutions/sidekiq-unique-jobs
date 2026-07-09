# frozen_string_literal: true

module Views
  module Landings
    # The home page — a marketing hero + feature grid + doc index, rendered by the
    # shared DocsUI::Landing component. Customize it entirely from config:
    # `c.landing.{eyebrow, title, lead, install, ctas, features}` in
    # config/initializers/docs_kit.rb. With no landing config it still renders a
    # minimal hero (the brand + the doc index), so this works out of the box.
    class Show < Phlex::HTML
      def view_template
        render DocsUI::Landing.new
      end
    end
  end
end
