Rails.application.config.to_prepare do
  Aicoo::ActivityIngestor.install_model_callbacks!(
    "Shop",
    "Article"
  )
end
