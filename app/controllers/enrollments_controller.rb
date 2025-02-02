class EnrollmentsController < ApplicationController
  RESPONSABLE_TRAITEMENT_LABEL = "responsable de traitement"
  DPO_LABEL = "délégué à la protection des données"

  before_action :authenticate_user!, except: [:public]
  before_action :set_enrollment, only: %i[show update trigger copy destroy update_owner update_rgpd_contact]

  # GET /enrollments
  def index
    @enrollments = policy_scope(Enrollment)
    if params.fetch(:target_api, false)
      @enrollments = @enrollments.where(target_api: params.fetch(:target_api, false))
    end

    begin
      sorted_by = JSON.parse(params.fetch(:sortedBy, "[]"))
      sorted_by.each do |sort_item|
        sort_item.each do |sort_key, sort_direction|
          next unless ["updated_at"].include? sort_key
          next unless %w[asc desc].include? sort_direction

          @enrollments = @enrollments.order("#{sort_key} #{sort_direction.upcase}")
        end
      end
    rescue JSON::ParserError
      # silently fail, if the sort is not formatted properly we do not apply it
    end

    begin
      filter = JSON.parse(params.fetch(:filter, "[]"))
      filter.each do |filter_item|
        filter_item.each do |filter_key, filter_value|
          next unless %w[id siret nom_raison_sociale target_api status user.email].include? filter_key
          filter_value = [filter_value] unless filter_value.is_a?(Array)
          sanitized_filter_value = filter_value.map { |f| Regexp.escape(f) }
          san_fil_val_without_accent = sanitized_filter_value.map { |f| ActiveSupport::Inflector.transliterate(f) }.join("|")
          next if san_fil_val_without_accent == ""

          if filter_key.start_with? "user."
            @enrollments = @enrollments.joins(
              "INNER JOIN users \"user\" ON \"user\".id = enrollments.user_id"
            )
            sanitized_filter_key = filter_key.split(".").map { |e| "\"#{e}\"" }.join(".")
          else
            sanitized_filter_key = "\"enrollments\".\"#{filter_key}\""
          end

          is_fuzzy = %w[id siret nom_raison_sociale user.email].include? filter_key

          @enrollments = @enrollments.where(
            "#{sanitized_filter_key}::varchar(255) ~* ?",
            is_fuzzy ? ".*(#{san_fil_val_without_accent}).*" : "^(#{san_fil_val_without_accent})$"
          )
        end
      end
    rescue JSON::ParserError
      # silently fail, if the filter is not formatted properly we do not apply it
    end

    page = params.fetch(:page, "0")
    size = params.fetch(:size, "10")
    size = "100" if size.to_i > 100
    @enrollments = @enrollments.page(page.to_i + 1).per(size.to_i)

    serializer = LightEnrollmentSerializer

    if params.fetch(:detailed, false)
      serializer = EnrollmentSerializer
    end

    render json: @enrollments,
           each_serializer: serializer,
           meta: pagination_dict(@enrollments),
           adapter: :json,
           root: "enrollments"
  end

  # GET /enrollments/1
  def show
    authorize @enrollment, :show?
    render json: @enrollment
  end

  # GET /enrollments/user
  def user
    # set an arbitrary limit to 100 to mitigate DDOS on this endpoint
    # we do not expect a user to have more than 100 enrollments within less than 4 organisations
    @enrollments = policy_scope(Enrollment)
      .order(updated_at: :desc)
      .limit(100)
    render json: @enrollments, each_serializer: UserEnrollmentListSerializer
  end

  # GET /enrollments/public
  def public
    enrollments = Enrollment
      .where(status: "validated")
      .order(updated_at: :desc)

    enrollments = enrollments.where(target_api: params.fetch(:target_api, false)) if params.fetch(:target_api, false)

    render json: enrollments, each_serializer: PublicEnrollmentListSerializer
  end

  # POST /enrollments
  def create
    target_api = params.fetch(:enrollment, {})["target_api"]
    unless EnrollmentMailer::MAIL_PARAMS.key?(target_api)
      raise ApplicationController::UnprocessableEntity, "Une erreur inattendue est survenue: API cible invalide. Aucun changement n’a été sauvegardé."
    end
    enrollment_class = "Enrollment::#{target_api.underscore.classify}".constantize
    @enrollment = enrollment_class.new

    authorize @enrollment

    @enrollment.assign_attributes(permitted_attributes(@enrollment))
    @enrollment.user = current_user

    if @enrollment.save
      @enrollment.events.create(name: "created", user_id: current_user.id)

      EnrollmentMailer.with(
        to: current_user.email,
        target_api: @enrollment.target_api,
        enrollment_id: @enrollment.id,
        template: "create_application"
      ).notification_email.deliver_later

      render json: @enrollment
    else
      render json: @enrollment.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /enrollments/1
  def update
    authorize @enrollment

    if @enrollment.update(permitted_attributes(@enrollment))
      @enrollment.events.create(name: "updated", user_id: current_user.id, diff: @enrollment.previous_changes)
      render json: @enrollment
    else
      render json: @enrollment.errors, status: :unprocessable_entity
    end
  end

  # PATCH /enrollment/1/trigger
  def trigger
    event = params[:event]
    unless Enrollment.state_machine.events.map(&:name).include?(event.to_sym)
      return render status: :bad_request, json: {
        message: ["event not permitted"]
      }
    end
    authorize @enrollment, "#{event}?".to_sym

    # We update userinfo when "event" is "send_application".
    # This is useful to prevent user that has been removed from organization, or has been deactivated
    # since first login, to submit authorization request illegitimately
    # Note that this feature need the access token to be stored in a clientside
    # sessions. This might be considered as a security weakness.
    if event == "send_application"
      # This is a defensive programming test because we must not update an user illegitimately
      if current_user.email == @enrollment.user.email
        begin
          refreshed_user = RefreshUser.call(session[:access_token])
          @enrollment.user.email_verified = refreshed_user.email_verified
          @enrollment.user.organizations = refreshed_user.organizations

          unless refreshed_user.email_verified
            raise ApplicationController::Forbidden, "L’accès à votre adresse email n’a pas pu être vérifié. Merci de vous rendre sur #{ENV.fetch("OAUTH_HOST")}/users/verify-email puis de cliquer sur 'Me renvoyer un code de confirmation'"
          end
          selected_organization = refreshed_user.organizations.find { |o| o["id"] == @enrollment.organization_id }
          if selected_organization.nil?
            raise ApplicationController::Forbidden, "Vous ne pouvez pas déposer une demande pour une organisation à laquelle vous n’appartenez pas. Merci de vous rendre sur #{ENV.fetch("OAUTH_HOST")}/users/join-organization?siret_hint=#{@enrollment.siret} puis de cliquer sur 'Rejoindre l’organisation'"
          end
        rescue ApplicationController::Forbidden => e
          raise
        rescue => e
          # If there is an error, we assume that the access token as expired
          # we force the logout so the token can be refreshed.
          # NB: if the error is something else, the user will keep clicking on "soumettre"
          # without any effect. We log this in case some user get stuck into this
          session.delete("access_token")
          session.delete("id_token")
          sign_out current_user
          puts "#{e.message.inspect} e.message"
          raise ApplicationController::AccessDenied, e.message
        end
      end
    end

    if @enrollment.send(
      event.to_sym,
      user_id: current_user.id,
      comment: params[:comment]
    )
      EnrollmentMailer.with(
        to: @enrollment.user.email,
        target_api: @enrollment.target_api,
        enrollment_id: @enrollment.id,
        template: event,
        message: params[:comment],
        comment_full_edit_mode: params[:commentFullEditMode]
      ).notification_email.deliver_later

      if event == "send_application"
        EnrollmentMailer.with(
          to: @enrollment.subscribers.map(&:email),
          target_api: @enrollment.target_api,
          enrollment_id: @enrollment.id,
          template: "notify_application_sent",
          applicant_email: current_user.email
        ).notification_email.deliver_later
      end
      if event == "validate_application" && @enrollment.responsable_traitement.present?
        RgpdMailer.with(
          to: @enrollment.responsable_traitement.email,
          target_api: @enrollment.target_api,
          enrollment_id: @enrollment.id,
          rgpd_role: RESPONSABLE_TRAITEMENT_LABEL,
          contact_label: @enrollment.responsable_traitement_label,
          owner_email: @enrollment.user.email,
          nom_raison_sociale: @enrollment.nom_raison_sociale,
          intitule: @enrollment.intitule
        ).rgpd_contact_email.deliver_later
      end
      if event == "validate_application" && @enrollment.dpo.present?
        RgpdMailer.with(
          to: @enrollment.dpo.email,
          target_api: @enrollment.target_api,
          enrollment_id: @enrollment.id,
          rgpd_role: DPO_LABEL,
          contact_label: @enrollment.dpo_label,
          owner_email: @enrollment.user.email,
          nom_raison_sociale: @enrollment.nom_raison_sociale,
          intitule: @enrollment.intitule
        ).rgpd_contact_email.deliver_later
      end

      render json: @enrollment
    else
      render status: :unprocessable_entity, json: @enrollment.errors
    end
  end

  # PATCH /enrollment/1/update_owner
  def update_owner
    authorize @enrollment

    if @enrollment.update(permitted_attributes(@enrollment))
      @enrollment.events.create(name: "updated", user_id: current_user.id, diff: @enrollment.previous_changes)
      render json: @enrollment
    else
      render json: @enrollment.errors, status: :unprocessable_entity
    end
  end

  # PATCH /enrollment/1/update_rgpd_contact
  def update_rgpd_contact
    authorize @enrollment

    if @enrollment.update(permitted_attributes(@enrollment))
      @enrollment.events.create(name: "updated", user_id: current_user.id, diff: @enrollment.previous_changes)
      if params[:enrollment].has_key?(:responsable_traitement_email)
        RgpdMailer.with(
          to: @enrollment.responsable_traitement.email,
          target_api: @enrollment.target_api,
          enrollment_id: @enrollment.id,
          rgpd_role: RESPONSABLE_TRAITEMENT_LABEL,
          contact_label: @enrollment.responsable_traitement_label,
          owner_email: @enrollment.user.email,
          nom_raison_sociale: @enrollment.nom_raison_sociale,
          intitule: @enrollment.intitule
        ).rgpd_contact_email.deliver_later
      end
      if params[:enrollment].has_key?(:dpo_email)
        RgpdMailer.with(
          to: @enrollment.dpo.email,
          target_api: @enrollment.target_api,
          enrollment_id: @enrollment.id,
          rgpd_role: DPO_LABEL,
          contact_label: @enrollment.dpo_label,
          owner_email: @enrollment.user.email,
          nom_raison_sociale: @enrollment.nom_raison_sociale,
          intitule: @enrollment.intitule
        ).rgpd_contact_email.deliver_later
      end

      render json: @enrollment
    else
      render json: @enrollment.errors, status: :unprocessable_entity
    end
  end

  # POST /enrollment/1/copy
  def copy
    copied_enrollment = @enrollment.copy current_user
    render json: copied_enrollment
  end

  # GET enrollments/1/copies
  def copies
    @enrollments = policy_scope(Enrollment)
      .where(copied_from_enrollment_id: params[:id])
    render json: @enrollments,
           each_serializer: LightEnrollmentSerializer,
           adapter: :json,
           root: "enrollments"
  end

  # GET enrollments/1/next_enrollments
  def next_enrollments
    @enrollments = policy_scope(Enrollment)
      .where(previous_enrollment_id: params[:id])
    render json: @enrollments,
           each_serializer: LightEnrollmentSerializer,
           adapter: :json,
           root: "enrollments"
  end

  def destroy
    @enrollment.destroy

    render status: :ok
  end

  private

  def set_enrollment
    @enrollment = policy_scope(Enrollment).find(params[:id])
  end

  def pundit_params_for(_record)
    params.fetch(:enrollment, {})
  end
end
