class SuelogRecord < ActiveRecord::Base
  class MissingDatabaseUrl < StandardError; end

  self.abstract_class = true

  before_create :raise_readonly!
  before_update :raise_readonly!
  before_destroy :raise_readonly!

  def self.configured?
    ENV["SUELOG_DATABASE_URL"].present?
  end

  def self.ensure_connection!
    raise MissingDatabaseUrl, "SUELOG_DATABASE_URL is not configured" unless configured?

    connect_to_suelog! unless connected_to_suelog?
    prepare_read_connection!
  end

  def self.connected_to_suelog?
    @suelog_database_url == ENV["SUELOG_DATABASE_URL"] && @suelog_database_url.present?
  end

  def self.prepare_read_connection!
    connection_pool.with_connection do |connection|
      connection.execute("SET statement_timeout = 5000")
      connection.execute("SET idle_in_transaction_session_timeout = 5000")
    end
  rescue ActiveRecord::StatementInvalid
    nil
  end

  def self.connection
    raise MissingDatabaseUrl, "SUELOG_DATABASE_URL is not configured" unless configured?
    connect_to_suelog! unless connected_to_suelog?
    super
  end

  def self.connect_to_suelog!
    establish_connection(ENV.fetch("SUELOG_DATABASE_URL"))
    @suelog_database_url = ENV.fetch("SUELOG_DATABASE_URL")
  end

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
