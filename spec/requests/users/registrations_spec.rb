require 'rails_helper'

RSpec.describe 'Users::Registrations', type: :request do
  let(:teacher_school) { create(:school) }
  let(:teacher) do
    create(:user, :teacher, :active_annual_teacher,
           annual_school: teacher_school,
           password: 'password123')
  end
  let(:admin) { create(:user, :admin, password: 'password123') }

  describe 'GET /users/sign_up' do
    it 'blocks public registration' do
      expect do
        get new_user_registration_path
      end.not_to change(User, :count)

      expect(response).to redirect_to(new_user_session_path)
      expect(response.body).not_to include('name="user[email]"')
    end
  end

  describe 'POST /users' do
    it 'does not create a public signup user' do
      expect do
        post user_registration_path, params: {
          user: {
            name: '외부 가입자',
            email: 'outsider@example.com',
            password: 'password123',
            password_confirmation: 'password123'
          }
        }
      end.not_to change(User, :count)

      expect(response).to redirect_to(new_user_session_path)
      expect(User.find_by(email: 'outsider@example.com')).to be_nil
      expect(User.find_by(name: '외부 가입자', role: 'student')).to be_nil
    end
  end

  describe 'GET /users/edit' do
    it 'keeps Teacher email optional and shows no email re-authentication field' do
      sign_in teacher
      get edit_user_registration_path

      document = Nokogiri::HTML(response.body)
      email = document.at_css('input[name="user[email]"]')
      expect(email).to be_present
      expect(email['required']).to be_nil
      expect(document.at_css('input[name="user[current_password]"]')).to be_nil
    end

    it 'requires Admin email and offers a password field for email changes' do
      sign_in admin
      get edit_user_registration_path

      document = Nokogiri::HTML(response.body)
      expect(document.at_css('input[name="user[email]"]')['required']).to be_present
      password = document.at_css('input[name="user[current_password]"]')
      expect(password).to be_present
      expect(password['required']).to be_nil
      expect(response.body).to include(I18n.t('users.registrations.email_change_password_hint'))
    end

    it 'allows teacher access' do
      sign_in teacher

      get edit_user_registration_path

      expect(response).to have_http_status(:ok)
    end

    it 'shows teacher avatar choices to teachers' do
      sign_in teacher

      get edit_user_registration_path

      expect(response.body).to include('name="user[avatar_key]"')
      expect(response.body).to include('value="teacherM04"')
      expect(response.body).to include('value="teacherF06"')
      expect(response.body).not_to include('name="user[avatar]"')
      expect(response.body).not_to include('value="boy01"')
      expect(response.body).not_to include('value="admin"')
      expect(response.body).not_to include('value="teacherM09"')
    end

    it 'shows teacher avatar choices to admins' do
      sign_in admin

      get edit_user_registration_path

      expect(response.body).to include('name="user[avatar_key]"')
      expect(response.body).to include('value="teacherM04"')
      expect(response.body).to include('value="teacherF06"')
      expect(response.body).to include('value="admin"')
      expect(response.body).not_to include('name="user[avatar]"')
      expect(response.body).not_to include('value="boy01"')
      expect(response.body).not_to include('value="teacherM09"')
    end
  end

  describe 'PATCH /users' do
    ['text/html', 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml'].each do |accept|
      [nil, 'wrong-password'].each do |current_password|
        it "rejects an Admin email change atomically with #{current_password.inspect} (#{accept})" do
          sign_in admin
          original = admin.attributes.slice('email', 'name', 'avatar_key', 'gender')

          patch user_registration_path, params: {
            user: { email: 'changed@example.com', name: '저장되면 안 됨', avatar_key: 'teacherF06',
              gender: 'female', current_password: current_password }
          }, headers: { 'ACCEPT' => accept }

          expect(response).to have_http_status(:unprocessable_content)
          expect(admin.reload.attributes.slice(*original.keys)).to eq(original)
          expect(controller.send(:resource).errors[:current_password]).to be_present
          document = Nokogiri::HTML(response.body)
          expect(document.at_css('input[name="user[current_password]"]')).to be_present
          expect(document.at_css('input[name="user[avatar_key]"]')).to be_present
          expect(response.body).to include(edit_account_password_path)
        end
      end
    end

    it 'changes Admin email with the current password and uses it for subsequent authentication' do
      sign_in admin
      previous_email = admin.email

      patch user_registration_path, params: {
        user: { email: 'changed@example.com', name: '변경 관리자', avatar_key: 'teacherF06',
          current_password: 'password123' }
      }

      expect(response).to redirect_to(edit_user_registration_path)
      expect(admin.reload).to have_attributes(email: 'changed@example.com', name: '변경 관리자', avatar_key: 'teacherF06')
      get edit_user_registration_path
      expect(response).to have_http_status(:ok)
      delete destroy_user_session_path
      post user_session_path, params: { user: { email: previous_email, password: 'password123' } }
      expect(response).to have_http_status(:unprocessable_content)
      post user_session_path, params: { user: { email: 'changed@example.com', password: 'password123' } }
      expect(response).to redirect_to(schools_path)
      expect(controller.current_user).to eq(admin)
    end

    it 'keeps normalized identical Admin email updates passwordless' do
      sign_in admin
      previous_email = admin.email
      patch user_registration_path, params: { user: { email: "  #{previous_email.upcase}  ", name: '수정 이름' } }

      expect(response).to redirect_to(edit_user_registration_path)
      expect(admin.reload).to have_attributes(email: previous_email, name: '수정 이름')
    end

    it 'keeps Admin profile updates passwordless when email is absent' do
      sign_in admin
      patch user_registration_path, params: { user: { name: '수정 이름', gender: 'female', avatar_key: 'teacherF06' } }

      expect(response).to redirect_to(edit_user_registration_path)
      expect(admin.reload).to have_attributes(name: '수정 이름', gender: 'female', avatar_key: 'teacherF06')
    end

    it 'still rejects blank Admin email even with the correct password' do
      sign_in admin
      original_email = admin.email
      patch user_registration_path, params: { user: { email: '', current_password: 'password123' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(admin.reload.email).to eq(original_email)
      expect(controller.send(:resource).errors[:email]).to be_present
    end

    it 'filters a forbidden avatar even during an authenticated Admin email change' do
      sign_in admin
      original_avatar = admin.avatar_key
      patch user_registration_path, params: {
        user: { email: 'changed@example.com', current_password: 'password123', avatar_key: 'boy01', gender: 'invalid' }
      }

      expect(response).to redirect_to(edit_user_registration_path)
      expect(admin.reload).to have_attributes(email: 'changed@example.com', avatar_key: original_avatar)
      expect(admin.gender).not_to eq('invalid')
    end

    it 'saves a Teacher profile with no email and permits contact email changes without a password' do
      teacher.update!(email: nil)
      sign_in teacher
      patch user_registration_path, params: { user: { name: '메일 없는 교사', email: '' } }
      expect(response).to redirect_to(edit_user_registration_path)
      expect(teacher.reload.name).to eq('메일 없는 교사')
      expect(teacher.email).to be_blank

      patch user_registration_path, params: { user: { email: 'contact@example.com' } }
      expect(response).to redirect_to(edit_user_registration_path)
      expect(teacher.reload.email).to eq('contact@example.com')

      patch user_registration_path, params: { user: { email: 'updated-contact@example.com' } }
      expect(response).to redirect_to(edit_user_registration_path)
      expect(teacher.reload.email).to eq('updated-contact@example.com')

      patch user_registration_path, params: { user: { name: '연락처 유지' } }
      expect(response).to redirect_to(edit_user_registration_path)
      expect(teacher.reload.email).to eq('updated-contact@example.com')
    end

    it 'updates teacher profile attributes without requiring the current password' do
      sign_in teacher

      patch user_registration_path, params: {
        user: {
          name: '바뀐 교사 이름',
          email: teacher.email
        }
      }

      expect(response).to redirect_to(edit_user_registration_path)
      expect(teacher.reload.name).to eq('바뀐 교사 이름')
    end

    it 'updates teacher gender and avatar_key without requiring the current password' do
      sign_in teacher

      patch user_registration_path, params: {
        user: {
          name: teacher.name,
          email: teacher.email,
          gender: 'female',
          avatar_key: 'teacherF06'
        }
      }

      expect(response).to redirect_to(edit_user_registration_path)
      expect(teacher.reload.gender).to eq('female')
      expect(teacher.avatar_key).to eq('teacherF06')
    end

    it 'does not allow a teacher to save a student avatar_key' do
      teacher.update!(avatar_key: 'teacherM04')
      sign_in teacher

      patch user_registration_path, params: {
        user: {
          name: teacher.name,
          email: teacher.email,
          avatar_key: 'boy01'
        }
      }

      expect(response).to redirect_to(edit_user_registration_path)
      expect(teacher.reload.avatar_key).to eq('teacherM04')
    end

    it 'updates admin profile attributes without requiring the current password' do
      sign_in admin

      patch user_registration_path, params: {
        user: {
          name: '바뀐 관리자 이름',
          email: admin.email
        }
      }

      expect(response).to redirect_to(edit_user_registration_path)
      expect(admin.reload.name).to eq('바뀐 관리자 이름')
    end

    it 'updates admin avatar_key with a teacher avatar key' do
      admin.update!(avatar_key: 'admin')
      sign_in admin

      patch user_registration_path, params: {
        user: {
          name: admin.name,
          email: admin.email,
          avatar_key: 'teacherM04'
        }
      }

      expect(response).to redirect_to(edit_user_registration_path)
      expect(admin.reload.avatar_key).to eq('teacherM04')
    end

    it 'does not allow an admin to save a student avatar_key' do
      admin.update!(avatar_key: 'teacherF06')
      sign_in admin

      patch user_registration_path, params: {
        user: {
          name: admin.name,
          email: admin.email,
          avatar_key: 'boy01'
        }
      }

      expect(response).to redirect_to(edit_user_registration_path)
      expect(admin.reload.avatar_key).to eq('teacherF06')
    end
  end

  describe 'DELETE /users' do
    it 'does not delete a teacher account' do
      sign_in teacher

      expect do
        delete user_registration_path
      end.not_to change(User, :count)

      expect(User.exists?(teacher.id)).to eq(true)
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(edit_user_registration_path)
      expect(flash[:alert]).to eq(I18n.t('users.registrations.account_deletion_disabled'))
    end

    it 'does not delete an admin account' do
      sign_in admin

      expect do
        delete user_registration_path
      end.not_to change(User, :count)

      expect(User.exists?(admin.id)).to eq(true)
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(edit_user_registration_path)
      expect(flash[:alert]).to eq(I18n.t('users.registrations.account_deletion_disabled'))
    end
  end

  describe 'GET /account/password/edit' do
    it 'allows teacher access' do
      sign_in teacher

      get edit_account_password_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH /account/password' do
    let(:turbo_headers) { { 'ACCEPT' => 'text/vnd.turbo-stream.html' } }

    it 'rejects teacher password changes without the current password' do
      sign_in teacher

      patch account_password_path,
            params: {
              user: {
                current_password: '',
                password: 'newpassword123',
                password_confirmation: 'newpassword123'
              }
            },
            headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(teacher.reload.valid_password?('password123')).to eq(true)
    end

    it 'updates the teacher password when the current password matches' do
      sign_in teacher

      patch account_password_path,
            params: {
              user: {
                current_password: 'password123',
                password: 'newpassword123',
                password_confirmation: 'newpassword123'
              }
            },
            headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(teacher.reload.valid_password?('newpassword123')).to eq(true)
    end
  end
end
