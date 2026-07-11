class SuelogRecord < ActiveRecord::Base
  class MissingDatabaseUrl < StandardError; end

  self.abstract_class = true

  before_create :raise_readonly!
  before_update :raise_readonly!
  before_destroy :raise_readonly!

  def self.configured?
    ENV["SUELOG_DATABASE_URL"].present?
  end

  def self.configure_connection!
    raise MissingDatabaseUrl, "SUELOG_DATABASE_URL is not configured" unless configured?

    establish_connection(:suelog) unless suelog_connection_pool?
  end

  def self.ensure_connection!
    configure_connection!
    prepare_read_connection!
  end

  def self.suelog_connection_pool?
    connection_pool.db_config.name == "suelog"
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::AdapterNotSpecified
    false
  end

  def self.prepare_read_connection!
    connection_pool.with_connection do |connection|
      connection.execute("SET statement_timeout = 5000")
      connection.execute("SET idle_in_transaction_session_timeout = 5000")
    end
  rescue ActiveRecord::StatementInvalid
    nil
  end

  configure_connection! if configured?

  def readonly?
    true
  end

  def delete
    raise_readonly!
  end

  def destroy
    raise_readonly!
  end

  private

  def raise_readonly!
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is read-only"
  end
end
