require "test_helper"
require "stringio"

module Aicoo
  class MemoryDiagnosticsTest < ActiveSupport::TestCase
    setup do
      @original_enabled = ENV["MEMORY_DIAGNOSTICS_ENABLED"]
      @original_threshold = ENV["MEMORY_DIAGNOSTICS_WARNING_MB"]
    end

    teardown do
      ENV["MEMORY_DIAGNOSTICS_ENABLED"] = @original_enabled
      ENV["MEMORY_DIAGNOSTICS_WARNING_MB"] = @original_threshold
    end

    test "does not log when diagnostics are disabled" do
      ENV["MEMORY_DIAGNOSTICS_ENABLED"] = "false"
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)

      Rails.stub(:logger, logger) do
        assert_equal "done", MemoryDiagnostics.measure("sample") { "done" }
      end

      assert_empty io.string
    end

    test "does not log when diagnostics are unset" do
      ENV.delete("MEMORY_DIAGNOSTICS_ENABLED")
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)

      Rails.stub(:logger, logger) do
        assert_equal "done", MemoryDiagnostics.measure("sample") { "done" }
      end

      assert_empty io.string
    end

    test "logs sanitized one line JSON when enabled" do
      ENV["MEMORY_DIAGNOSTICS_ENABLED"] = "true"
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)

      Rails.stub(:logger, logger) do
        MemoryDiagnostics.stub(:current_rss_mb, 123.4) do
          MemoryDiagnostics.measure("sample", context: { path: "/owner", password: "hidden" }) { "done" }
        end
      end

      assert_includes io.string, "[MemoryDiagnostics]"
      assert_includes io.string, '"name":"sample"'
      assert_includes io.string, '"path":"/owner"'
      refute_includes io.string, "hidden"
      refute_includes io.string, "password"
      refute_includes io.string, "cookie"
    end

    test "logs warning when memory increase exceeds threshold" do
      ENV["MEMORY_DIAGNOSTICS_ENABLED"] = "true"
      ENV["MEMORY_DIAGNOSTICS_WARNING_MB"] = "50"
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)
      samples = [ 100.0, 160.0 ]

      Rails.stub(:logger, logger) do
        MemoryDiagnostics.stub(:current_rss_mb, -> { samples.shift || 160.0 }) do
          MemoryDiagnostics.measure("heavy") { "done" }
        end
      end

      assert_includes io.string, "[MemoryDiagnostics][WARNING]"
      assert_includes io.string, '"rss_delta_mb":60.0'
    end

    test "reraises original exception and logs error memory" do
      ENV["MEMORY_DIAGNOSTICS_ENABLED"] = "true"
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)

      Rails.stub(:logger, logger) do
        MemoryDiagnostics.stub(:current_rss_mb, 100.0) do
          error = assert_raises(RuntimeError) do
            MemoryDiagnostics.measure("boom") { raise "original failure" }
          end
          assert_equal "original failure", error.message
        end
      end

      assert_includes io.string, '"event":"error"'
      assert_includes io.string, '"error_class":"RuntimeError"'
    end

    test "continues when rss sampling fails" do
      ENV["MEMORY_DIAGNOSTICS_ENABLED"] = "true"
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)

      Rails.stub(:logger, logger) do
        MemoryDiagnostics.stub(:linux_rss_kb, -> { raise "rss unavailable" }) do
          MemoryDiagnostics.stub(:ps_rss_kb, -> { raise "ps unavailable" }) do
            assert_equal "done", MemoryDiagnostics.measure("rss_failure") { "done" }
          end
        end
      end

      assert_includes io.string, '"name":"rss_failure"'
      assert_includes io.string, '"event":"finish"'
    end
  end
end
