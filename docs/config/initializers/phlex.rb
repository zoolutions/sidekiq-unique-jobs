# frozen_string_literal: true

# Phlex autoload namespaces for this docs site:
#   app/views       → Views::   (pages, e.g. Views::Docs::Pages::Installation)
#   app/components  → Components:: (a Phlex::Kit; your own components, if any)
module Views
end

module Components
  extend Phlex::Kit
end

Rails.autoloaders.main.push_dir(Rails.root.join("app", "views"), namespace: Views)
Rails.autoloaders.main.push_dir(Rails.root.join("app", "components"), namespace: Components)
