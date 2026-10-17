require "minitest/autorun"
require "minitest/mock"
require "tmpdir"
require "fileutils"
require "json"
require "cgi"
require "open3"
require_relative "support/jekyll_build"
require_relative "support/candidate_fixture"

class ReportBuildTest < Minitest::Test
  def with_data
    Dir.mktmpdir do |root|
      path = File.join(root, "input")
      FileUtils.mkdir_p(path)
      FileUtils.cp(Dir[File.join(CandidateFixture::PATH, "*.json")], path)
      yield root, path
    end
  end

  def inputs(path)
    Dir[File.join(path, "*")].to_h { |file| [file, File.binread(file)] }
  end

  def build(destination, path: nil, baseurl: "", serving: false, converter: nil)
    converter ||= ->(_html, pdf) { File.write(pdf, "%PDF-1.4 simulated") }
    AlojamentoLocal::ReportPdf.stub(:convert, converter) do
      JekyllBuild.build(run_dir: path, destination: destination, baseurl: baseurl, serving: serving)
    end
  end

  def test_standalone_counts_downloads_and_inputs_unchanged
    with_data do |root, path|
      before = inputs(path)
      destination = File.join(root, "report")
      build(destination, path: path)
      assert_equal %w[LICENSE NOTICE report.html report.pdf snapshots], Dir.children(destination).sort
      assert_equal before, inputs(path)
      html = File.read(File.join(destination, "report.html"))
      assert_includes html, "<b>12</b>"
      assert_includes html, "<b>13</b>"
      assert_includes html, "<b>7</b>"
      normalized = html.gsub(/\s+/, " ")
      assert_includes normalized, "RNAL descarregado em 2024-07-01"
      assert_includes normalized, "Anúncios de 2024-06-01 (descarregados em 2024-06-03)"
      assert_includes html, "candidate-012"
      assert_includes html, "Município oficial diferente do observado"
      assert_includes html, "???"
      refute_includes html, "https://www.airbnb.com/rooms/"
      file = AlojamentoLocal::CandidateDataset::FILE
      assert_equal [file], Dir.children(File.join(destination, "snapshots", "candidate"))
      assert_equal File.binread(File.join(path, file)), File.binread(File.join(destination, "snapshots", "candidate", file))
      assert_raises(RuntimeError) { build(path, path: path) }
      assert_equal before, inputs(path)
    end
  end

  def test_site_and_standalone_share_report_and_do_not_read_old_snapshots
    with_data do |root, path|
      standalone = File.join(root, "standalone")
      full = File.join(root, "site")
      build(standalone, path: path)
      AlojamentoLocal::PublicSnapshot.stub(:load, ->(*) { flunk "Site must not read old snapshots" }) do
        build(full, baseurl: "/preview")
      end
      assert_equal File.binread(File.join(standalone, "report.html")), File.binread(File.join(full, "report.html"))
      report = File.read(File.join(full, "report.html"))
      assert_includes report, "Isenção declarada"
      refute_includes report, "<th>Correspondência</th>"
      refute_includes report, "<th>Isenção</th>"
      refute_includes report, "Limite próximo:"
      refute_includes report, "Fontes de localização observada concordantes"
      assert_equal 24, Dir[File.join(full, "freguesias", "*", "index.html")].size
      %w[index.html freguesias/index.html freguesias/arroios/index.html metodologia.html].each do |file|
        html = File.read(File.join(full, file))
        refute_match(/NaN|Infinity/, html)
        refute_includes html, "/runs/"
        visible = html.gsub(/<[^>]*>/, " ")
        refute_match(/\blistings?\b|fixtures?|pipeline|snapshot de teste/i, visible)
      end
      homepage = File.read(File.join(full, "index.html"))
      assert_includes homepage, 'id="opening-title"'
      assert_includes homepage, 'id="investigacao"'
      assert_includes homepage, 'id="signal-unresolved"'
      unresolved_card = homepage.match(/<article[^>]*aria-labelledby="signal-unresolved".*?<\/article>/m)[0]
      refute_includes unresolved_card, "???"
      assert_match(/>2<\/span>\s*anúncios sem licença identificável/, unresolved_card)
      assert_match(/Campo vazio<\/span>\s*<strong>1<\/strong>/, unresolved_card)
      assert_match(/Valor não reconhecido<\/span>\s*<strong>1<\/strong>/, unresolved_card)
      assert_equal 2, unresolved_card.scan("width:50.0%").size
      assert_includes homepage, 'id="signal-repeated"'
      repeated_card = homepage.match(/<article[^>]*aria-labelledby="signal-repeated".*?<\/article>/m)[0]
      refute_includes repeated_card, "???"
      assert_match(/>2<\/span>\s*anúncios com o mesmo número/, repeated_card)
      assert_match(/Mais de 5 km<\/span>\s*<strong>1<\/strong>/, repeated_card)
      assert_includes repeated_card, "width:100.0%"
      assert_match(/1 número AL,\s*associado\s+a\s*2 anúncios/, repeated_card)
      assert_includes repeated_card, "Distância máxima ao RNAL"
      refute_includes repeated_card, "Distância máxima entre localizações"
      assert_includes homepage, 'id="signal-outside"'
      outside_card = homepage.match(/<article[^>]*aria-labelledby="signal-outside".*?<\/article>/m)[0]
      refute_includes outside_card, "???"
      assert_match(/Algarve<\/span>\s*<strong>1<\/strong>/, outside_card)
      assert_includes outside_card, "width:100.0%"
      assert_includes outside_card, "anúncio com licença registada fora de Lisboa"
      assert_match(/Distribuição por NUTS II\s*do\s*1 anúncio/, outside_card)
      assert_includes homepage, "Freguesias com mais candidatos AL"
      assert_includes homepage, "Não há possibilidade de saber a realidade"
      refute_includes homepage, "Dados sintéticos de demonstração"
      assert_includes homepage, "/preview/snapshots/candidate/snapshot.json"
      assert_includes homepage, %(href="#{CGI.escapeHTML(AlojamentoLocal::Analysis::Data::OFFICIAL_URL)}")
      methodology = File.read(File.join(full, "metodologia.html"))
      assert_includes methodology, %(href="#{CGI.escapeHTML(AlojamentoLocal::Analysis::Data::OFFICIAL_URL)}")
      assert_includes methodology, %(href="#{AlojamentoLocal::Analysis::Data::AIRBNB_DATA_PAGE}")
      refute_includes methodology, "A distribuição regional apresenta ???"
      refute_match(/\blistings?\b/i, report.gsub(/<[^>]*>/, " "))
      normalized = homepage.gsub(/\s+/, " ")
      assert_includes normalized, "Descarregado em 2024-07-01"
      assert_match(/Anúncios de <time[^>]*>2024-06-01<\/time>/, normalized)
      refute_includes normalized, "· descarregados em"
      assert_match(/<strong[^>]*>\s*17\s*<\/strong>\s*<p[^>]*>registos no concelho de Lisboa/, homepage)
      assert_includes homepage, "12 candidatos</tspan>"
      assert_includes homepage, 'aria-label="Com número AL: 8 AL"'
      assert_includes homepage, 'aria-label="Sem número AL: 4 AL"'
      assert_includes homepage, 'class="overlap-base overlap-base--airbnb"'
      refute_includes homepage, "overlap-unresolved-bubble"
      refute_includes homepage, "overlap-label--unresolved"
      assert_includes homepage, "???"
      refute_match(/<circle[^>]*r=""/, homepage)
      assert_includes File.read(File.join(full, "index.html")), "/preview/report.html"
      AlojamentoLocal::SiteChecker.check(full)
    end
  end

  def test_escaping_and_zero_distance
    with_data do |root, path|
      file = File.join(path, "snapshot.json")
      data = JSON.parse(File.read(file))
      data["candidates"][0]["official_match"]["type"] = '<script>alert("example")</script>'
      data["candidates"][0]["official_match"]["distance_km"] = 0
      File.write(file, JSON.generate(data))
      output = File.join(root, "report")
      build(output, path: path)
      html = File.read(File.join(output, "report.html"))
      assert_includes html, "&lt;script&gt;alert(&quot;example&quot;)&lt;/script&gt;"
      refute_includes html, "<script>"
      assert_includes html.gsub(/\s+/, " "), "Distância RNAL (km): 0"
    end
  end

  def test_conversion_failure_stops_build_and_preserves_inputs
    with_data do |root, path|
      before = inputs(path)
      output = File.join(root, "report")
      error = assert_raises(RuntimeError) do
        build(output, path: path, converter: ->(html, _) {
          assert File.file?(html)
          raise "converter failed"
        })
      end
      assert_equal "converter failed", error.message
      assert_equal before, inputs(path)
      refute File.exist?(File.join(output, "report.pdf"))
    end
  end

  def test_public_build_removes_stale_private_and_historical_outputs
    with_data do |root, _|
      output = File.join(root, "site")
      %w[private-reports/example runs/old].each do |folder|
        FileUtils.mkdir_p(File.join(output, folder))
        File.write(File.join(output, folder, "report.html"), "private")
      end
      build(output)
      refute Dir.exist?(File.join(output, "private-reports"))
      refute Dir.exist?(File.join(output, "runs"))
      text, status = Open3.capture2e(RbConfig.ruby, File.expand_path("../scripts/audit_publication.rb", __dir__), "--artifact", output)
      assert status.success?, text
      # New public fields are allowed, extra detailed fields are rejected.
      file = File.join(output, "snapshots", "candidate", "snapshot.json")
      data = JSON.parse(File.read(file))
      data["candidates"][0]["name"] = "private name"
      File.write(file, JSON.generate(data))
      text, status = Open3.capture2e(RbConfig.ruby, File.expand_path("../scripts/audit_publication.rb", __dir__), "--artifact", output)
      refute status.success?, text
      assert_includes text, "snapshot inválido"
    end
  end

  def test_skip_pdf_only_applies_to_local_serving
    previous = ENV["SKIP_PDF"]
    ENV["SKIP_PDF"] = "1"
    with_data do |root, path|
      output = File.join(root, "site")
      build(output, serving: true, converter: ->(*) { flunk "Serving skips conversion" })
      refute File.exist?(File.join(output, "report.pdf"))
      refute_includes File.read(File.join(output, "index.html")), 'href="/report.pdf"'
      build(output)
      assert File.exist?(File.join(output, "report.pdf"))
      build(File.join(root, "standalone"), path: path)
      assert File.exist?(File.join(root, "standalone", "report.pdf"))
    end
  ensure
    ENV["SKIP_PDF"] = previous
  end
end
