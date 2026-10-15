require "test_helper"

class AdminRolesTest < ActiveSupport::TestCase
  test "new accounts default to mural admin and predicates express product access" do
    user = Admin::User.new(username: "artist", password: "a-long-test-password")
    assert user.mural_admin?
    assert user.can_administer_murals?
    assert_not user.can_administer_canyon?
    user.role = :canyon_admin
    assert user.canyon_admin?
    assert user.can_administer_canyon?
    assert_not user.can_administer_murals?
    user.role = :super_admin
    assert user.super_admin?
    assert user.can_administer_canyon?
    assert user.can_administer_murals?
  end

  test "role is required constrained and never defaults to super admin in SQL" do
    user = Admin::User.new(username: "artist", password: "a-long-test-password", role: "unknown")
    assert_not user.valid?
    user.role = nil
    assert_not user.valid?
    assert_equal "mural_admin", Admin::User.columns_hash.fetch("role").default
    assert_raises(ActiveRecord::StatementInvalid) do
      Admin::User.transaction(requires_new: true) { Admin::User.insert_all!([ { username: "bad-role", password_digest: "digest", role: "unknown" } ]) }
    end
    assert_raises(ActiveRecord::NotNullViolation) do
      Admin::User.transaction(requires_new: true) { Admin::User.insert_all!([ { username: "null-role", password_digest: "digest", role: nil } ]) }
    end
  end

  test "final active super admin cannot be demoted or deactivated" do
    last = Admin::User.create!(username: "owner", password: "a-long-test-password", role: :super_admin)
    assert_not last.update(active: false)
    assert_includes last.errors.full_messages, "At least one active super admin must remain."
    last.reload
    assert_not last.update(role: :mural_admin)
    assert last.reload.super_admin?
    assert last.active?
    backup = Admin::User.create!(username: "backup", password: "a-long-test-password", role: :super_admin)
    assert last.update(role: :canyon_admin)
    assert_not backup.update(active: false)
    assert backup.reload.active?
  end
end
