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
end
