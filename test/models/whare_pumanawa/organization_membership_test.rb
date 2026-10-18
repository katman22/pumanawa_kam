require "test_helper"

class WharePumanawa::OrganizationMembershipTest < ActiveSupport::TestCase
  setup do
    @organization = WharePumanawa::Organization.create!(name: "Studio A")
    @admin = Admin::User.create!(username: "org-owner", password: "a-long-test-password", role: :organization_admin)
  end

  test "required associations unique pair multiple organizations and safe cleanup" do
    assert_not WharePumanawa::OrganizationMembership.new.valid?
    membership = @organization.organization_memberships.create!(admin_user: @admin)
    assert_not @organization.organization_memberships.new(admin_user: @admin).valid?
    other = WharePumanawa::Organization.create!(name: "Studio B")
    other.organization_memberships.create!(admin_user: @admin)
    assert_equal 2, @admin.organization_memberships.count
    assert_not @organization.destroy
    assert_raises(ActiveRecord::RecordNotUnique) do
      membership.class.transaction(requires_new: true) do
        membership.class.insert_all!([ { organization_id: @organization.id, admin_user_id: @admin.id } ])
      end
    end
    @admin.destroy!
    assert_empty @organization.reload.organization_memberships
    assert @organization.destroy
  end

  test "database requires valid foreign keys and non-null associations" do
    %i[organization_id admin_user_id].each do |key|
      attrs = { organization_id: @organization.id, admin_user_id: @admin.id }
      assert_raises(ActiveRecord::NotNullViolation) do
        WharePumanawa::OrganizationMembership.transaction(requires_new: true) { WharePumanawa::OrganizationMembership.insert_all!([ attrs.merge(key => nil) ]) }
      end
      assert_raises(ActiveRecord::InvalidForeignKey) do
        WharePumanawa::OrganizationMembership.transaction(requires_new: true) { WharePumanawa::OrganizationMembership.insert_all!([ attrs.merge(key => -1) ]) }
      end
    end
  end

  test "only active organization admins are eligible without granting scope through stale rows" do
    @organization.organization_memberships.create!(admin_user: @admin)
    %i[canyon_admin mural_admin].each do |role|
      @admin.reload
      @admin.update!(role: role)
      assert_not @organization.organization_memberships.new(admin_user: @admin).valid?
      assert_not @admin.can_administer_organization?(@organization)
    end
    @admin.reload.update!(role: :organization_admin, active: false)
    assert_not @admin.can_view_organization?(@organization)
    assert_empty @admin.administrable_organizations
    assert_empty @admin.associable_contributors
  end
end
