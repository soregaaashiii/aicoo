class EnableAutoRevisionQueueByDefault < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:aicoo_auto_revision_settings)

    execute <<~SQL.squish
      UPDATE aicoo_auto_revision_settings
      SET enabled = TRUE, updated_at = CURRENT_TIMESTAMP
      WHERE enabled = FALSE
    SQL
  end

  def down
    # Intentionally keep the queue setting as-is. This migration only moves
    # AICOO to the intended safe default: generate AutoRevisionTask records,
    # without enabling auto merge or auto deploy.
  end
end
