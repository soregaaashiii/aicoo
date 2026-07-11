require "test_helper"

class SuelogRecordTest < ActiveSupport::TestCase
  test "suelog external models are read only" do
    shop = Suelog::Shop.allocate

    assert shop.readonly?
    assert_raises(ActiveRecord::ReadOnlyRecord) { shop.delete }
  end
end
