# frozen_string_literal: true

# docs-kit's chrome renders lucide icons via rails_icons. Set the default library
# and sync the icon set once:
#
#   bin/rails g rails_icons:sync --library=lucide   # syncs the default (lucide) set
#
# (The chrome uses: menu, palette, list, file-code, search, info, lightbulb,
# triangle-alert. Syncing the whole lucide set covers those + any you add.)
RailsIcons.configure do |config|
  config.default_library = "lucide"
end
