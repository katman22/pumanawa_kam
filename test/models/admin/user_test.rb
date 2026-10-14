require "test_helper"

class AdminUserTest < ActiveSupport::TestCase
  test "user normalizes username and stores a password hash" do
    user = Admin::User.create!(username: "  Artist  ", password: "a-long-test-password")
    assert_equal "artist", user.username
    assert user.active?
    assert user.authenticate("a-long-test-password")
    assert_not user.authenticate("wrong")
    assert_not_equal "a-long-test-password", user.password_digest
  end

  test "username password and boolean are validated" do
    assert_not Admin::User.new(username: " ", password: "a-long-test-password").valid?
    assert_not Admin::User.new(username: "artist").valid?
    assert_not Admin::User.new(username: "artist", password: "short").valid?
    assert_not Admin::User.new(username: "artist", password: "p" * 11).valid?
    assert Admin::User.new(username: "artist", password: "p" * 12).valid?
    assert_not Admin::User.new(username: "artist", password: "x" * 73).valid?
    assert_not Admin::User.new(username: "artist", password: "a-long-test-password", active: nil).valid?
  end

  test "username uniqueness is enforced in model and database" do
    user = Admin::User.create!(username: "artist", password: "a-long-test-password")
    assert_not Admin::User.new(username: " ARTIST ", password: "a-long-test-password").valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      Admin::User.transaction(requires_new: true) { Admin::User.insert_all!([ { username: "artist", password_digest: user.password_digest } ]) }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      Admin::User.transaction(requires_new: true) { Admin::User.insert_all!([ { username: " ARTIST ", password_digest: user.password_digest } ]) }
    end
  end

  test "database requires username password digest and active" do
    [ { username: nil, password_digest: "digest" }, { username: "artist", password_digest: nil },
      { username: "artist", password_digest: "digest", active: nil } ].each do |attributes|
      assert_raises(ActiveRecord::NotNullViolation) do
        Admin::User.transaction(requires_new: true) { Admin::User.insert_all!([ attributes ]) }
      end
    end
  end
end
