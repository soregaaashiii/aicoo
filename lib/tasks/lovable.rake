namespace :aicoo do
  desc "Diagnose the Lovable LP generation, publication, and learning pipeline"
  task diagnose_lovable_pipeline: :environment do
    result = Aicoo::Lovable::PipelineDiagnostic.new(probe: ENV.fetch("PROBE", "1") == "1").call
    puts "lovable_configuration=#{result.configuration.to_json}"
    puts "lovable_probe_status=#{result.probe_status}"
    puts "lovable_probe_error=#{result.probe_error}"
    result.rows.each do |row|
      puts [
        "business_id=#{row.business_id}",
        "business=#{row.business_name}",
        "lovable_connected=#{row.connected}",
        "connection_mode=#{row.connection_mode}",
        "prompt_generated=#{row.prompt_generated}",
        "send_success=#{row.send_success}",
        "preview_acquired=#{row.preview_acquired}",
        "version_saved=#{row.version_saved}",
        "last_sent_at=#{row.last_sent_at&.iso8601}",
        "preview_url=#{row.preview_url}",
        "project_id=#{row.project_id}",
        "version_count=#{row.version_count}",
        "revision_count=#{row.revision_count}",
        "publication_status=#{row.publication_status}",
        "deploy_status=#{row.deploy_status}",
        "learning_status=#{row.learning_status}",
        "last_error=#{row.last_error}"
      ].join(" ")
    end
    result.summary.each { |key, value| puts "#{key}=#{value}" }
  end

  desc "Diagnose Lovable landing page version learning and improvement candidates"
  task diagnose_landing_page_learning: :environment do
    result = Aicoo::Lovable::LandingPageLearningDiagnostic.new(business_id: ENV["BUSINESS_ID"]).call
    result.rows.each do |row|
      puts [
        "business_id=#{row.business_id}",
        "business=#{row.business_name}",
        "current_version=#{row.current_version}",
        "best_version=#{row.best_version}",
        "cvr=#{row.cvr}",
        "roi=#{row.roi}",
        "confidence=#{row.confidence}",
        "learning_status=#{row.learning_status}",
        "action_candidate_count=#{row.candidate_count}",
        "improvements=#{row.improvements.to_json}",
        "lovable_sent=#{row.lovable_sent_count}",
        "published_versions=#{row.published_version_count}",
        "benchmark_source=#{row.benchmark_source}",
        "skip_reason=#{row.skip_reason}"
      ].join(" ")
    end
    result.summary.each { |key, value| puts "#{key}=#{value}" }
  end

  desc "Diagnose Lovable official Build with URL prompt and version handoff"
  task diagnose_lovable_build_url: :environment do
    result = Aicoo::Lovable::BuildUrlDiagnostic.new(business_id: ENV["BUSINESS_ID"]).call
    result.rows.each do |row|
      puts [
        "business_id=#{row.business_id}",
        "business=#{row.business_name}",
        "prompt_generated=#{row.prompt_generated}",
        "build_url_generated=#{row.build_url_generated}",
        "prompt_version=#{row.prompt_version}",
        "version=#{row.version}",
        "preview_saved=#{row.preview_saved}",
        "learning=#{row.learning_status}",
        "action_candidate_count=#{row.action_candidate_count}",
        "launcher=#{row.launcher}",
        "last_error=#{row.last_error}"
      ].join(" ")
    end
    result.summary.each { |key, value| puts "#{key}=#{value}" }
  end
end
