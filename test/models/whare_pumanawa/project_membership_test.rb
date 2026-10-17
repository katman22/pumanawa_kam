require "test_helper"

class WharePumanawa::ProjectMembershipTest < ActiveSupport::TestCase
  setup do
    @project = WharePumanawa::Project.create!(name: "Collection")
    @admin = Admin::User.create!(username: "artist", password: "a-long-test-password", role: :mural_admin)
  end

  test "required associations uniqueness and safe deletion" do
    assert_not WharePumanawa::ProjectMembership.new.valid?
    membership = @project.project_memberships.create!(admin_user: @admin)
    assert_equal @project, membership.project
    assert_equal @admin, membership.admin_user
    assert_not @project.project_memberships.new(admin_user: @admin).valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      membership.class.transaction(requires_new: true) { membership.class.insert_all!([ { project_id: @project.id, admin_user_id: @admin.id } ]) }
    end
    assert_not @project.destroy
    membership.destroy!
    assert @project.reload.destroy
  end

  test "database enforces not null and foreign keys" do
    %i[project_id admin_user_id].each do |field|
      attrs = { project_id: @project.id, admin_user_id: @admin.id }.merge(field => nil)
      assert_raises(ActiveRecord::NotNullViolation) do
        WharePumanawa::ProjectMembership.transaction(requires_new: true) { WharePumanawa::ProjectMembership.insert_all!([ attrs ]) }
      end
      assert_raises(ActiveRecord::InvalidForeignKey) do
        WharePumanawa::ProjectMembership.transaction(requires_new: true) { WharePumanawa::ProjectMembership.insert_all!([ attrs.merge(field => -1) ]) }
      end
    end
  end

  test "capabilities combine membership with role and active state without implicit future access" do
    other = WharePumanawa::Project.create!(name: "Other")
    mural = @project.murals.create!(title: "Mural")
    assert_empty @admin.administrable_projects
    assert_not @admin.can_administer_project?(@project)
    assert_not @admin.can_administer_mural?(mural)
    @project.project_memberships.create!(admin_user: @admin)
    assert @admin.can_administer_project?(@project)
    assert @admin.can_administer_mural?(mural)
    assert_equal [ @project.id ], @admin.administrable_projects.pluck(:id)
    assert_equal [ mural.id ], @admin.administrable_murals.pluck(:id)
    assert_not @admin.can_administer_project?(other)
    @admin.update!(role: :canyon_admin)
    assert_not @admin.can_administer_project?(@project)
    assert_empty @admin.administrable_murals
    assert_not @project.project_memberships.new(admin_user: @admin).valid?
    @admin.reload
    @admin.update!(role: :mural_admin, active: false)
    assert_not @admin.can_administer_mural?(mural)
  end

  test "super admin bypasses membership including unassigned murals" do
    owner = Admin::User.create!(username: "owner", password: "a-long-test-password", role: :super_admin)
    mural = WharePumanawa::Mural.create!(title: "Unassigned")
    assert owner.can_administer_project?(@project)
    assert owner.can_administer_mural?(mural)
    assert_equal [ @project.id ], owner.administrable_projects.pluck(:id)
    assert_includes owner.administrable_murals, mural
    assert_empty owner.project_memberships
  end
end
