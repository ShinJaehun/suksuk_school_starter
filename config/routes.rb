Rails.application.routes.draw do
  post "/rails/active_storage/direct_uploads",
    to: ->(_env) { [404, { "Content-Type" => "text/plain" }, ["Not Found"]] }

  devise_for :users, controllers: {
    registrations: "users/registrations",
    sessions: "users/sessions"
  }
  devise_scope :user do
    get "/account/password/edit", to: "users/registrations#edit_password", as: :edit_account_password
    patch "/account/password", to: "users/registrations#update_password", as: :account_password
  end

  get "/schools/:school_id/teacher_login", to: "teacher_sessions#new", as: :school_teacher_login
  post "/schools/:school_id/teacher_login", to: "teacher_sessions#create"
  get "/account/forced_password/edit", to: "users/forced_passwords#edit", as: :edit_forced_password
  patch "/account/forced_password", to: "users/forced_passwords#update", as: :forced_password

  get "/student_login", to: "student_sessions#new", as: :new_student_session
  delete "/student_logout", to: "student_sessions#destroy", as: :destroy_student_session
  get "/c/:student_login_token/login", to: "student_sessions#new", as: :public_student_login
  post "/c/:student_login_token/login", to: "student_sessions#create"
  get "/student", to: "student_profile#show", as: :student_profile
  get "/student/pin/edit", to: "student_profile#edit", as: :edit_student_pin
  patch "/student/pin", to: "student_profile#update", as: :student_pin
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  # get "up" => "rails/health#show", as: :rails_health_check

  resources :teachers, only: %i[index new create edit update destroy] do
    get :classroom_options, on: :collection
    patch :deactivate, on: :member
    patch :reactivate, on: :member
    patch :reissue_temporary_password, on: :member
  end

  resources :classrooms, except: [:edit, :update] do
    patch :deactivate, on: :member
    patch :reactivate, on: :member

    resource :members, only: :show, module: :classrooms
    get "members/students/names/edit",
      to: "classrooms/members#edit_student_names",
      as: :edit_member_student_names
    patch "members/students/name",
      to: "classrooms/members#update_student_names",
      as: :member_student_names
    get "members/students/pin/edit",
      to: "classrooms/members#edit_student_pin",
      as: :edit_member_student_pin
    patch "members/students/pin",
      to: "classrooms/members#update_student_pin",
      as: :member_student_pin

    member do
      get :student_login_info,
        to: "classrooms/student_logins#student_login_info"
      get :student_login_qr,
        to: "classrooms/student_logins#student_login_qr"
      get "student_login_qr/download",
        to: "classrooms/student_logins#download_student_login_qr",
        as: :download_student_login_qr
      patch :regenerate_student_login_token,
        to: "classrooms/student_logins#regenerate_student_login_token"
    end

    resources :students, controller: "classroom_students", only: [:new, :create, :show, :edit, :update, :destroy] do
      collection do
        get :bulk_new,
          to: "classroom_students/bulk_registrations#new"
        post :bulk_preview,
          to: "classroom_students/bulk_registrations#preview"
        post :bulk_create,
          to: "classroom_students/bulk_registrations#create"
      end
      member do
        patch :deactivate
        patch :reactivate
      end
    end
  end

  get "/classrooms/:id/edit",
    to: "classrooms/settings#edit",
    as: :edit_classroom
  patch "/classrooms/:id",
    to: "classrooms/settings#update"
  put "/classrooms/:id",
    to: "classrooms/settings#update"

  resources :schools, only: %i[index show edit update] do
    resources :school_years, only: :create
    resource :planning, only: :show, controller: "school_planning"
  end

  # Defines the root path route ("/")
  root "home#index"

  namespace :admin do
    root to: redirect("/schools")

    resources :schools, only: %i[new create] do
      patch :deactivate, on: :member
      patch :reactivate, on: :member
      resources :school_managers, only: :create, path: :managers
      delete "managers/:user_id", to: "school_managers#destroy", as: :manager
    end
  end

end
