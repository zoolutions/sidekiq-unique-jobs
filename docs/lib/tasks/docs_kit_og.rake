# frozen_string_literal: true

# Generate this site's social-share (Open Graph / Twitter) images by
# screenshotting its OWN landing page, so a shared link renders a real card of
# your docs — not the neutral placeholder docs-kit ships. Run it whenever the
# landing page changes materially:
#
#   bin/rails docs_kit:og
#
# It boots the app, serves it locally, screenshots "/" at the standard sizes, and
# writes them into app/assets/images/og/. Point c.seo.og_image at the result
# (the default "og/og.png" already matches). This is a documented, manual routine
# (like phlex-reactive's vendored-client re-sync) — never run automatically, so a
# machine without a headless browser is never blocked at deploy time.
#
# It shells out to a headless-browser CLI you already have; it is NOT a docs-kit
# runtime dependency. Supported (auto-detected, first one found wins), override
# with DOCS_KIT_SHOT:
#   * shot-scraper   (https://shot-scraper.datasette.io) — `pipx install shot-scraper`
#   * chromium/chrome headless --screenshot
# Set DOCS_KIT_OG_URL to shoot a deployed URL instead of booting locally.
namespace :docs_kit do
  desc "Screenshot the landing page into app/assets/images/og/{og,twitter,square}.png"
  task og: :environment do
    require "docs_kit/og_generator"

    sizes = {
      "og.png" => [ 1200, 630 ],       # Open Graph / twitter summary_large_image
      "twitter.png" => [ 1024, 512 ],  # Twitter summary card
      "square.png" => [ 600, 600 ]     # square fallback (some chat clients)
    }
    out_dir = Rails.root.join("app/assets/images/og")

    DocsKit::OgGenerator.new(
      url: ENV.fetch("DOCS_KIT_OG_URL", nil),
      out_dir: out_dir,
      sizes: sizes,
      shooter: ENV.fetch("DOCS_KIT_SHOT", nil)
    ).call

    puts "✅ Wrote #{sizes.keys.join(', ')} to #{out_dir.to_s.sub("#{Dir.pwd}/", '')}"
    puts "   Point c.seo.og_image at one of them (default \"og/og.png\" already does)."
  end
end
