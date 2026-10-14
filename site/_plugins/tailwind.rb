# frozen_string_literal: true

# Compile after Jekyll writes the pages so its cleanup cannot remove the CSS.
Jekyll::Hooks.register :site, :post_write do |site|
  next if site.config["report_only"]
  root = File.expand_path("../..", __dir__)
  output = File.join(site.dest, "assets", "story.css")
  Jekyll.logger.info "Tailwind:", "Compiling #{output}"
  system("npm", "run", "site:css", "--", "--output", output, chdir: root, exception: true)
end
