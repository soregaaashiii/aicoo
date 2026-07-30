Rails.application.config.after_initialize do
  Aicoo::SystemModePerformance.install!
end
