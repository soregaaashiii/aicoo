class AddGenerationSourceToActionCandidates < ActiveRecord::Migration[8.0]
  SEED_TITLES = [
    "吸えログで中崎町の記事を書く",
    "名刺共有アプリの権限管理を改善する",
    "新規事業候補のSERP調査をする"
  ].freeze

  def change
    add_column :action_candidates, :generation_source, :string, null: false, default: "manual"
    add_index :action_candidates, :generation_source

    reversible do |dir|
      dir.up do
        quoted_titles = SEED_TITLES.map { |title| quote(title) }.join(", ")
        execute <<~SQL.squish
          UPDATE action_candidates
          SET generation_source = 'seed'
          WHERE title IN (#{quoted_titles})
        SQL
      end
    end
  end
end
