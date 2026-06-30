# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
AicooLabSetting.find_or_create_by!(id: 1) do |setting|
  setting.monthly_budget_yen = 5_000
  setting.minimum_sample_pv = 1_000
  setting.hourly_cost_yen = 1_226
  setting.auto_generate_enabled = true
  setting.free_experiments_continue_after_budget = true
end

businesses = [
  { name: "吸えログ", description: "喫煙所・喫煙可能店舗を軸にしたSEOメディア。", status: "launched" },
  { name: "名刺共有アプリ", description: "名刺情報の共有と権限管理を扱うSaaS候補。", status: "building" },
  { name: "新規事業探索", description: "SERP調査・市場調査から次の種を探すフォルダ。", status: "researching" }
].index_by { |business| business[:name] }

businesses.each_value do |attributes|
  Business.find_or_create_by!(name: attributes[:name]) do |business|
    business.description = attributes[:description]
    business.status = attributes[:status]
  end
end

CodexPromptRule.ensure_defaults! if defined?(CodexPromptRule)
