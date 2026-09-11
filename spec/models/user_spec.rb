require "rails_helper"

RSpec.describe User, type: :model do
  describe "operational teacher predicates" do
    it "distinguishes an active teacher account from a current operational teacher" do
      school = create(:school)
      active_year = create(:school_year, :active, school: school, year: 2026)
      active_teacher = create(:user, :teacher, school_year: active_year,
        login_id: "active-teacher", school_role: "member")
      inactive_teacher = create(:user, :teacher, school_year: active_year,
        login_id: "inactive-teacher", school_role: "member", active: false)
      planning_teacher = create(:user, :teacher,
        school_year: create(:school_year, school: school, year: 2027),
        login_id: "planning-teacher", school_role: "member")
      archived_teacher = create(:user, :teacher,
        school_year: create(:school_year, :archived, school: school, year: 2025),
        login_id: "archived-teacher", school_role: "member")

      expect(active_teacher).to be_active_teacher
      expect(active_teacher).to be_current_operational_teacher
      expect(inactive_teacher).not_to be_active_teacher
      expect(inactive_teacher).not_to be_current_operational_teacher
      expect(planning_teacher).to be_active_teacher
      expect(planning_teacher).not_to be_current_operational_teacher
      expect(archived_teacher).to be_active_teacher
      expect(archived_teacher).not_to be_current_operational_teacher

      school.update!(active: false)
      expect(active_teacher).not_to be_current_operational_teacher
    end

    it "requires every operational condition for current manager authority" do
      school = create(:school)
      manager = create(:user, :teacher, :active_annual_teacher,
        annual_school: school, annual_school_role: "manager")

      expect(manager).to be_current_operational_manager

      manager.school_year.update!(status: :archived)
      expect(manager).not_to be_current_operational_manager
    end
  end

  describe "role-specific email requirements" do
    it "allows a teacher without email" do
      expect(build(:user, :teacher, :active_annual_teacher,
        annual_school: create(:school), email: nil)).to be_valid
    end

    it "requires email for a global admin" do
      admin = build(:user, :admin, email: nil)

      expect(admin).not_to be_valid
      expect(admin.errors[:email]).to be_present
    end
  end

  describe "teacher credential foundation" do
    it "defaults users to no forced password change" do
      teacher = create(:user, :teacher, :active_annual_teacher, annual_school: create(:school))

      expect(teacher).not_to be_password_change_required
    end

    it "exposes issued and received credential audit events" do
      actor = create(:user, :admin)
      teacher = create(:user, :teacher, :active_annual_teacher, annual_school: create(:school))
      event = TeacherCredentialEvent.create!(
        actor_user: actor,
        teacher_user: teacher,
        action: :temporary_password_issued
      )

      expect(actor.issued_teacher_credential_events).to contain_exactly(event)
      expect(teacher.teacher_credential_events).to contain_exactly(event)
    end
  end

  describe "annual account invariants" do
    it "requires every annual identity field for a teacher except grade" do
      teacher = build(:user, :teacher, :active_annual_teacher,
        annual_school: create(:school), annual_grade: nil)

      expect(teacher).to be_valid
      %i[school_year login_id school_role].each do |attribute|
        invalid_teacher = teacher.dup
        invalid_teacher.public_send("#{attribute}=", nil)

        expect(invalid_teacher).not_to be_valid
      end
      expect(teacher.dup.tap { |user| user.grade = 0 }).not_to be_valid
      expect(teacher.dup.tap { |user| user.grade = 7 }).not_to be_valid
    end

    it "requires admin annual authority fields to be absent" do
      school_year = create(:school_year)

      user = build(:user, :admin, school_year: school_year, login_id: "annual-id",
        school_role: "member", grade: 4)

      expect(user).not_to be_valid
    end

    it "enforces role-dependent annual fields at the database boundary" do
      teacher = create(:user, :teacher, :active_annual_teacher, annual_school: create(:school))
      admin = create(:user, :admin)

      %i[school_year_id login_id school_role].each do |attribute|
        expect { teacher.update_columns(attribute => nil) }
          .to raise_error(ActiveRecord::StatementInvalid)
      end
      expect do
        admin.update_columns(school_year_id: teacher.school_year_id,
          login_id: "admin-login", school_role: "member", grade: 4)
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects an unknown school year at the database boundary" do
      teacher = create(:user, :teacher, :active_annual_teacher, annual_school: create(:school))

      expect do
        teacher.update_columns(school_year_id: -1)
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end

    it "rejects duplicate login IDs within one school year" do
      school_year = create(:school_year)
      first_teacher = create(:user, :teacher, :active_annual_teacher,
        annual_school: school_year.school, school_year: school_year, login_id: "tara0411")
      second_teacher = create(:user, :teacher, :active_annual_teacher,
        annual_school: school_year.school, school_year: school_year)

      expect do
        second_teacher.update_columns(school_year_id: school_year.id, login_id: "tara0411")
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "normalizes login IDs to lowercase canonical storage" do
      teacher = create(:user, :teacher, :active_annual_teacher,
        annual_school: create(:school), login_id: " TARA0411 ")

      expect(teacher.login_id).to eq("tara0411")
    end

    it "rejects uppercase and surrounding whitespace at the database boundary" do
      teacher = create(:user, :teacher, :active_annual_teacher, annual_school: create(:school))

      expect { teacher.update_columns(login_id: "TARA0411") }
        .to raise_error(ActiveRecord::StatementInvalid)
      expect { teacher.update_columns(login_id: " tara0411 ") }
        .to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects a normalized duplicate within one school year at the database boundary" do
      school_year = create(:school_year)
      create(:user, :teacher, :active_annual_teacher,
        annual_school: school_year.school, school_year: school_year, login_id: "tara0411")
      teacher = create(:user, :teacher, :active_annual_teacher,
        annual_school: school_year.school, school_year: school_year)

      expect { teacher.update_columns(login_id: "TARA0411") }
        .to raise_error(ActiveRecord::StatementInvalid)
    end

    it "allows the same login ID in different school years" do
      school = create(:school)
      first_year = create(:school_year, :archived, school: school, year: 2025)
      second_year = create(:school_year, :active, school: school, year: 2026)
      expect do
        create(:user, :teacher, :active_annual_teacher,
          annual_school: school, school_year: first_year, login_id: "tara0411")
        create(:user, :teacher, :active_annual_teacher,
          annual_school: school, school_year: second_year, login_id: "tara0411")
      end.not_to raise_error
    end

    it "rejects an unsupported school role at the database boundary" do
      teacher = create(:user, :teacher, :active_annual_teacher, annual_school: create(:school))

      expect do
        teacher.update_columns(school_role: "owner")
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects grades below the supported range at the database boundary" do
      teacher = create(:user, :teacher, :active_annual_teacher, annual_school: create(:school))

      expect do
        teacher.update_columns(grade: 0)
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects grades above the supported range at the database boundary" do
      teacher = create(:user, :teacher, :active_annual_teacher, annual_school: create(:school))

      expect do
        teacher.update_columns(grade: 7)
      end.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects a second manager teacher within one school year" do
      school_year = create(:school_year)
      first_teacher = create(:user, :teacher, :active_annual_teacher,
        annual_school: school_year.school, school_year: school_year, annual_school_role: "manager")
      second_teacher = create(:user, :teacher, :active_annual_teacher,
        annual_school: school_year.school, school_year: school_year)

      expect do
        second_teacher.update_columns(school_year_id: school_year.id, school_role: "manager")
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows manager teachers in different school years" do
      first_year = create(:school_year)
      second_year = create(:school_year)
      create(:user, :teacher, :active_annual_teacher,
        annual_school: first_year.school, school_year: first_year, annual_school_role: "manager")

      expect do
        create(:user, :teacher, :active_annual_teacher,
          annual_school: second_year.school, school_year: second_year, annual_school_role: "manager")
      end.not_to raise_error
    end

    it "keeps admin accounts free of annual fields" do
      admin = create(:user, :admin)

      expect(admin).to have_attributes(
        school_year_id: nil,
        login_id: nil,
        school_role: nil,
        grade: nil
      )
    end
  end

  describe ".avatar_keys_for" do
    it "returns male teacher avatar keys" do
      expect(described_class.avatar_keys_for("male")).to eq(%w[teacherM01 teacherM02 teacherM03 teacherM04 teacherM05 teacherM06 teacherM07 teacherM08])
    end

    it "returns female teacher avatar keys" do
      expect(described_class.avatar_keys_for("female")).to eq(%w[teacherF01 teacherF02 teacherF03 teacherF04 teacherF05 teacherF06])
    end

    it "returns admin avatar keys" do
      expect(described_class.avatar_keys_for("admin")).to eq(["admin"])
    end

    it "returns an empty array for unknown gender" do
      expect(described_class.avatar_keys_for("unknown")).to eq([])
    end
  end

  describe ".avatar_keys_for_role" do
    it "returns only teacher avatars for teachers" do
      expect(described_class.avatar_keys_for_role("teacher")).to eq(
        described_class::TEACHER_MALE_AVATAR_KEYS + described_class::TEACHER_FEMALE_AVATAR_KEYS
      )
    end

    it "returns admin and teacher avatars for admins" do
      expect(described_class.avatar_keys_for_role("admin")).to eq(
        described_class::ADMIN_AVATAR_KEYS + described_class::TEACHER_AVATAR_KEYS
      )
    end
  end

  it "validates gender values" do
    user = build(:user, :admin, gender: "other")

    expect(user).not_to be_valid
  end

  it "validates avatar_key values" do
    user = build(:user, :admin, avatar_key: "boy99")

    expect(user).not_to be_valid
  end

  it "allows teacher and admin avatar_key values" do
    school = create(:school)

    expect(build(:user, :teacher, :active_annual_teacher,
      annual_school: school, gender: "male", avatar_key: "teacherM08")).to be_valid
    expect(build(:user, :teacher, :active_annual_teacher,
      annual_school: school, gender: "female", avatar_key: "teacherF06")).to be_valid
    expect(build(:user, :admin, gender: nil, avatar_key: "admin")).to be_valid
    expect(build(:user, :admin, gender: nil, avatar_key: "teacherM08")).to be_valid
  end

  it "rejects role-incompatible avatar_key changes" do
    expect(build(:user, :teacher, avatar_key: "boy01")).not_to be_valid
    expect(build(:user, :admin, avatar_key: "girl01")).not_to be_valid
  end

  it "allows unrelated updates for a legacy role-incompatible avatar_key" do
    teacher = create(:user, :teacher, :active_annual_teacher,
      annual_school: create(:school), avatar_key: "teacherM01")
    teacher.update_column(:avatar_key, "boy01")

    expect(teacher.update(name: "Updated Teacher")).to eq(true)
  end

  describe "role-specific Devise credentials" do
    it "allows teacher email to be absent but requires it for admins" do
      expect(build(:user, :teacher, :active_annual_teacher,
        annual_school: create(:school), email: nil)).to be_valid
      expect(build(:user, :admin, email: nil)).not_to be_valid
    end

    it "requires password for new teachers" do
      teacher = build(:user, :teacher, :active_annual_teacher,
        annual_school: create(:school), password: nil)

      expect(teacher).not_to be_valid
    end

    it "keeps case-insensitive email uniqueness for staff accounts" do
      create(:user, :teacher, :active_annual_teacher,
        annual_school: create(:school), email: "staff@example.com")

      expect(build(:user, :admin, email: "STAFF@example.com")).not_to be_valid
    end

  end

  describe "teacher account status" do
    it "defaults to active and exposes status scopes and predicates" do
      school = create(:school)
      teacher = create(:user, :teacher, :active_annual_teacher, annual_school: school)
      inactive_teacher = create(:user, :teacher, :active_annual_teacher,
        annual_school: school, active: false)

      expect(teacher).to be_active
      expect(teacher).to be_active_teacher
      expect(inactive_teacher).to be_inactive
      expect(described_class.active).to include(teacher)
      expect(described_class.inactive).to include(inactive_teacher)
    end

    it "blocks only inactive teachers from Devise authentication" do
      expect(build(:user, :teacher, active: false).active_for_authentication?).to eq(false)
      expect(build(:user, :teacher).active_for_authentication?).to eq(true)
      expect(build(:user, :admin).active_for_authentication?).to eq(true)
    end
  end

end
