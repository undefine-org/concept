defmodule ConceptWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides

  alias AshAuthentication.Phoenix.{Components, SignInLive, ResetLive, ConfirmLive}

  override SignInLive do
    set :root_class, "ora-auth-root"
  end

  override ResetLive do
    set :root_class, "ora-auth-root"
  end

  override ConfirmLive do
    set :root_class, "ora-auth-root"
  end

  override Components.SignIn do
    set :root_class, "ora-auth-card"
    set :strategy_class, "ora-auth-strategy"
    set :show_banner, false
    set :authentication_error_container_class, ""
    set :authentication_error_text_class, ""
    set :strategy_display_order, :forms_first
  end

  override Components.Reset do
    set :root_class, "ora-auth-card"
    set :strategy_class, "ora-auth-strategy"
    set :show_banner, false
  end

  override Components.Confirm do
    set :root_class, "ora-auth-card"
    set :strategy_class, "ora-auth-strategy"
    set :show_banner, false
  end

  override Components.Banner do
    set :root_class, nil
    set :href_class, nil
    set :href_url, nil
    set :image_class, nil
    set :dark_image_class, nil
    set :image_url, nil
    set :dark_image_url, nil
    set :text_class, nil
    set :text, nil
  end

  override Components.HorizontalRule do
    set :root_class, "ora-auth-hr"
    set :hr_outer_class, "hidden"
    set :hr_inner_class, "hidden"
    set :text_outer_class, "contents"
    set :text_inner_class, "contents"
    set :text, "or"
  end

  override Components.Flash do
    set :message_class_info, "ora-auth-flash-info"
    set :message_class_error, "ora-auth-flash-error"
  end

  override Components.Password do
    set :root_class, ""
    set :interstitial_class, "ora-auth-interstitial"
    set :toggler_class, "ora-auth-toggler"
    set :sign_in_toggle_text, "Already have an account?"
    set :register_toggle_text, "Need an account?"
    set :reset_toggle_text, "Forgot your password?"
    set :show_first, :sign_in
    set :hide_class, "ora-auth-hide"
    set :register_form_module, Components.Password.RegisterForm
    set :sign_in_form_module, Components.Password.SignInForm
    set :reset_form_module, Components.Password.ResetForm
  end

  override Components.Password.SignInForm do
    set :root_class, ""
    set :label_class, "ora-auth-title"
    set :form_class, "ora-auth-form"
    set :slot_class, "ora-auth-slot"
    set :button_text, "Sign in"
    set :disable_button_text, "Signing in …"
  end

  override Components.Password.RegisterForm do
    set :root_class, ""
    set :label_class, "ora-auth-title"
    set :form_class, "ora-auth-form"
    set :slot_class, "ora-auth-slot"
    set :button_text, "Register"
    set :disable_button_text, "Registering …"
  end

  override Components.Password.ResetForm do
    set :root_class, ""
    set :label_class, "ora-auth-title"
    set :form_class, "ora-auth-form"
    set :slot_class, "ora-auth-slot"
    set :button_text, "Request reset password link"
    set :disable_button_text, "Requesting …"

    set :reset_flash_text,
        "If this user exists in our system, you will be contacted with password reset instructions shortly."
  end

  override Components.Password.Input do
    set :field_class, "ora-auth-field"
    set :label_class, "ora-auth-label"
    set :input_class, "ora-auth-input"
    set :input_class_with_error, "ora-auth-input ora-auth-input-error"
    set :submit_class, "ora-auth-submit"
    set :password_input_label, "Password"
    set :password_confirmation_input_label, "Password Confirmation"
    set :identity_input_label, "Email"
    set :identity_input_placeholder, nil
    set :error_ul, "ora-auth-error-ul"
    set :error_li, "ora-auth-error-li"
    set :input_debounce, 350
    set :remember_me_class, "ora-auth-remember-me"
    set :remember_me_input_label, "Remember me"
    set :checkbox_class, "ora-auth-checkbox"
    set :checkbox_label_class, "ora-auth-checkbox-label"
  end

  override Components.Reset.Form do
    set :root_class, ""
    set :label_class, "ora-auth-title"
    set :form_class, "ora-auth-form"
    set :spacer_class, "ora-auth-spacer"
    set :disable_button_text, "Changing password …"
  end

  override Components.Confirm.Input do
    set :submit_class, "ora-auth-submit"
    set :submit_label, "Confirm"
  end

  override Components.OAuth2 do
    set :root_class, "ora-auth-field"
    set :link_class, "ora-auth-submit"
    set :icon_class, nil
    set :icon_src, nil
  end

  override Components.Apple do
    set :root_class, "ora-auth-field"
    set :link_class, "ora-auth-submit"
    set :icon_class, nil
  end
end
