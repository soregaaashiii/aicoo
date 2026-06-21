require "test_helper"

class DataImportsControllerTest < ActionDispatch::IntegrationTest
  test "uploads csv data for a business" do
    file = Tempfile.new([ "gsc", ".csv" ])
    file.write("query,clicks\nnakazakicho smoking,10\n")
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: "gsc.csv")

    assert_difference -> { DataSource.count }, 1 do
      assert_difference -> { DataImport.count }, 1 do
        post business_data_imports_url(businesses(:suelog)), params: {
          data_import: {
            source_type: "gsc",
            name: "GSC test",
            status: "active",
            file: upload
          }
        }
      end
    end

    data_import = DataImport.last
    assert_redirected_to business_url(businesses(:suelog))
    assert_equal "gsc.csv", data_import.filename
    assert_equal 1, data_import.row_count
    assert_includes data_import.raw_text, "nakazakicho smoking"
  ensure
    file&.close
    file&.unlink
  end
end
