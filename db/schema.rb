# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_14_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "classrooms", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "class_label", null: false
    t.datetime "created_at", null: false
    t.integer "grade", null: false
    t.bigint "school_year_id", null: false
    t.string "student_login_token", null: false
    t.datetime "updated_at", null: false
    t.index ["school_year_id", "grade", "class_label"], name: "index_classrooms_on_school_year_grade_class_label", unique: true
    t.index ["school_year_id"], name: "index_classrooms_on_school_year_id"
    t.index ["student_login_token"], name: "index_classrooms_on_student_login_token", unique: true
    t.check_constraint "class_label::text <> ''::text AND length(class_label::text) <= 50 AND class_label::text = btrim(class_label::text) AND \"right\"(class_label::text, 1) <> '반'::text", name: "chk_classrooms_class_label_canonical"
  end

  create_table "homeroom_assignments", force: :cascade do |t|
    t.bigint "classroom_id", null: false
    t.datetime "created_at", null: false
    t.date "ended_on"
    t.date "started_on", null: false
    t.bigint "teacher_id", null: false
    t.datetime "updated_at", null: false
    t.index ["classroom_id"], name: "index_current_homeroom_assignment_per_classroom", unique: true, where: "(ended_on IS NULL)"
    t.index ["classroom_id"], name: "index_homeroom_assignments_on_classroom_id"
    t.index ["teacher_id"], name: "index_current_homeroom_assignment_per_teacher", unique: true, where: "(ended_on IS NULL)"
    t.index ["teacher_id"], name: "index_homeroom_assignments_on_teacher_id"
    t.check_constraint "ended_on IS NULL OR ended_on >= started_on", name: "chk_homeroom_assignment_date_order"
  end

  create_table "school_years", force: :cascade do |t|
    t.datetime "automatic_rollover_attempted_at"
    t.datetime "created_at", null: false
    t.bigint "school_id", null: false
    t.string "status", default: "planning", null: false
    t.datetime "updated_at", null: false
    t.integer "year", null: false
    t.index ["school_id", "year"], name: "index_school_years_on_school_id_and_year", unique: true
    t.index ["school_id"], name: "index_school_years_on_school_id"
    t.index ["school_id"], name: "index_school_years_on_unique_active_school", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["school_id"], name: "index_school_years_on_unique_planning_school", unique: true, where: "((status)::text = 'planning'::text)"
    t.check_constraint "status::text = ANY (ARRAY['planning'::character varying::text, 'active'::character varying::text, 'archived'::character varying::text])", name: "chk_school_years_status"
    t.check_constraint "year >= 1000 AND year <= 9999", name: "chk_school_years_year_range"
  end

  create_table "schools", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "color_key", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_schools_on_active"
  end

  create_table "students", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "avatar_key"
    t.bigint "classroom_id", null: false
    t.datetime "created_at", null: false
    t.string "gender"
    t.string "name", null: false
    t.integer "student_number"
    t.string "student_pin_digest"
    t.datetime "updated_at", null: false
    t.index ["classroom_id", "student_number"], name: "index_students_on_active_classroom_number", unique: true, where: "(active AND (student_number IS NOT NULL))"
    t.index ["classroom_id"], name: "index_students_on_classroom_id"
    t.check_constraint "gender IS NULL OR (gender::text = ANY (ARRAY['boy'::character varying::text, 'girl'::character varying::text]))", name: "chk_students_gender"
    t.check_constraint "student_number IS NULL OR student_number > 0", name: "chk_students_student_number_positive"
  end

  create_table "teacher_credential_events", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_user_id", null: false
    t.datetime "created_at", null: false
    t.bigint "teacher_user_id", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_user_id"], name: "index_teacher_credential_events_on_actor_user_id"
    t.index ["teacher_user_id"], name: "index_teacher_credential_events_on_teacher_user_id"
    t.check_constraint "action::text = ANY (ARRAY['temporary_password_issued'::character varying::text, 'temporary_password_reissued'::character varying::text])", name: "chk_teacher_credential_events_action"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "avatar_key"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "encrypted_password", default: "", null: false
    t.string "gender"
    t.integer "grade"
    t.string "login_id"
    t.string "name"
    t.boolean "password_change_required", default: false, null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", null: false
    t.string "school_role"
    t.bigint "school_year_id"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role", "active"], name: "index_users_on_role_and_active"
    t.index ["school_year_id", "login_id"], name: "index_users_on_school_year_id_and_login_id", unique: true
    t.index ["school_year_id"], name: "index_users_on_school_year_id"
    t.index ["school_year_id"], name: "index_users_on_unique_manager_school_year", unique: true, where: "(((role)::text = 'teacher'::text) AND ((school_role)::text = 'manager'::text) AND (school_year_id IS NOT NULL))"
    t.check_constraint "grade IS NULL OR grade >= 1 AND grade <= 6", name: "chk_users_grade_range"
    t.check_constraint "login_id IS NULL OR login_id::text <> ''::text AND login_id::text = btrim(login_id::text) AND login_id::text = lower(login_id::text)", name: "chk_users_login_id_canonical"
    t.check_constraint "role::text = 'teacher'::text AND school_year_id IS NOT NULL AND login_id IS NOT NULL AND school_role IS NOT NULL OR role::text <> 'teacher'::text AND school_year_id IS NULL AND login_id IS NULL AND school_role IS NULL AND grade IS NULL", name: "chk_users_annual_fields_by_role"
    t.check_constraint "role::text = ANY (ARRAY['teacher'::character varying::text, 'admin'::character varying::text])", name: "chk_users_role"
    t.check_constraint "school_role IS NULL OR (school_role::text = ANY (ARRAY['member'::character varying::text, 'manager'::character varying::text]))", name: "chk_users_school_role"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "classrooms", "school_years"
  add_foreign_key "homeroom_assignments", "classrooms"
  add_foreign_key "homeroom_assignments", "users", column: "teacher_id"
  add_foreign_key "school_years", "schools"
  add_foreign_key "students", "classrooms"
  add_foreign_key "teacher_credential_events", "users", column: "actor_user_id"
  add_foreign_key "teacher_credential_events", "users", column: "teacher_user_id"
  add_foreign_key "users", "school_years"
end
