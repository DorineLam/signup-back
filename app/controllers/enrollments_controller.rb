# frozen_string_literal: true

class EnrollmentsController < ApplicationController
  before_action :authenticate!, except: [:public]
  before_action :set_enrollment, only: %i[show update update_contacts trigger destroy]

  # GET /enrollments
  def index
    @enrollments = enrollments_scope

    if params.fetch(:archived, false)
      @enrollments = @enrollments.archived
    end

    if params.fetch(:state, false)
      @enrollments = @enrollments.state(params.fetch(:state, false))
    end

    if params.fetch(:fournisseur_de_donnees, false)
      @enrollments = @enrollments.fournisseur_de_donnees(params.fetch(:fournisseur_de_donnees, false))
    end

    if not params.fetch(:archived, false) and not params.fetch(:state, false)
      @enrollments = @enrollments.pending
    end

    render json: @enrollments.map { |e| serialize(e) }
  end

  # GET /enrollments/1
  def show
    render json: serialize(@enrollment)
  end

  # GET /enrollments/public
  def public
    enrollments = Enrollment
      .where("state = ?", 'validated')
      .order(updated_at: :desc)

    if params.fetch(:fournisseur_de_donnees, false)
      enrollments = enrollments.where("fournisseur_de_donnees = ?", params.fetch(:fournisseur_de_donnees, ''))
    end

    render json: enrollments, each_serializer: Enrollment::PublicEnrollmentListSerializer
  end

  # POST /enrollments
  def create
    @enrollment = enrollments_scope.new(enrollment_params)

    authorize @enrollment, :create?

    @enrollment.user = current_user

    if @enrollment.save
      current_user.add_role(:applicant, @enrollment)

      EnrollmentMailer.with(
        to: current_user.email,
        target_api: @enrollment.fournisseur_de_donnees,
        enrollment_id: @enrollment.id,
        template: 'create_application',
      ).notification_email.deliver_later

      render json: @enrollment, status: :created, location: enrollment_url(@enrollment)
    else
      render json: @enrollment.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /enrollments/1
  def update
    @enrollment.attributes = enrollment_params
    authorize @enrollment, :update?

    if @enrollment.save
      render json: serialize(@enrollment)
    else
      render json: @enrollment.errors, status: :unprocessable_entity
    end
  end

  # PATCH /enrollments/1/update_contacts
  def update_contacts
    @enrollment.attributes = enrollment_params
    authorize @enrollment, :update_contacts?

    if @enrollment.save
      EnrollmentMailer.with(
          to: @enrollment.admins.map(&:email),
          target_api: @enrollment.fournisseur_de_donnees,
          enrollment_id: @enrollment.id,
          template: 'update_contacts',
          applicant_email: current_user.email
      ).notification_email.deliver_later

      render json: serialize(@enrollment)
    else
      render json: @enrollment.errors, status: :unprocessable_entity
    end
  end

  # PATCH /enrollment/1/trigger
  def trigger
    authorize @enrollment, "#{event_param}?".to_sym

    if event_param.in?(['refuse_application', 'review_application']) and not message_params.has_key?(:messages_attributes)
      return render status: :bad_request, json: {
        message: ['Le commentaire est obligatoire.']
      }
    end
    
    if message_params.has_key?(:messages_attributes)
      params =  {
        messages_attributes: message_params[:messages_attributes].map! {|h| h.merge(category: event_param.to_s)}
      }
      @enrollment.update(params)
    end

    if @enrollment.send(event_param.to_sym, user: current_user)
      personified_role_names = {
        'send_application' => :application_sender,
        'validate_application' => :application_validater,
        'review_application' => :application_reviewer,
        'refuse_application' => :application_refuser
      }
      current_user&.add_role(personified_role_names[event_param], @enrollment)

      EnrollmentMailer.with(
        to: @enrollment.user.email,
        target_api: @enrollment.fournisseur_de_donnees,
        enrollment_id: @enrollment.id,
        template: event_param,
        message: message_params.fetch(:messages_attributes, [{}]).first[:content]
      ).notification_email.deliver_later

      if event_param == 'send_application'
        EnrollmentMailer.with(
          to: @enrollment.admins.map(&:email),
          target_api: @enrollment.fournisseur_de_donnees,
          enrollment_id: @enrollment.id,
          template: 'notify_application_sent',
          applicant_email: current_user.email
        ).notification_email.deliver_later
      end

      render json: serialize(@enrollment)
    else
      render status: :unprocessable_entity, json: @enrollment.errors
    end
  end

  # DELETE /enrollments/1
  def destroy
    authorize @enrollment, :delete?
    @enrollment.destroy
  end

  def serialize(enrollment)
    Rails.application.eager_load!
    policy_class = Object.const_get("#{enrollment.class.to_s}Policy")
    enrollment.as_json(
      include: [{ documents: { methods: :type } }, { messages: { include: :sender } }],
    ).merge('acl' => Hash[
      policy_class.acl_methods.map do |method|
        [method.to_s.delete('?'), policy_class.new(current_user, enrollment).send(method)]
      end
    ])
  end

  private

  def set_enrollment
    @enrollment = enrollments_scope.find(params[:id])
  end

  def enrollment_class
    type = params.fetch(:enrollment, {})[:fournisseur_de_donnees]
    type = %w[dgfip api-particulier api-entreprise franceconnect api-droits-cnam].include?(type) ? type : nil
    class_name = type ? "Enrollment::#{type.underscore.classify}" : 'Enrollment'
    class_name.constantize
  end

  def enrollments_scope
    EnrollmentPolicy::Scope.new(current_user, enrollment_class).resolve
  end

  def enrollment_params
    params
      .fetch(:enrollment, {})
      .permit(*policy(@enrollment || enrollment_class.new).permitted_attributes)
      .tap do |whitelisted_params|
        enrollment = params.fetch(:enrollment, {})
        scopes = enrollment[:scopes]
        destinataires = enrollment.fetch(:donnees, {})[:destinataires]
        whitelisted_params[:scopes] = scopes.permit! if scopes.present?
        whitelisted_params.fetch(:donnees, {})[:destinataires] = destinataires.permit! if destinataires.present?
    end
  end

  def message_params
    params.fetch(:enrollment, {}).permit(messages_attributes: [:content])
  end

  def event_param
    event = params[:event]
    raise EventNotPermitted unless enrollment_class.state_machine.events.map(&:name).include?(event.to_sym)
    event
  end

  class EventNotPermitted < StandardError; end

  rescue_from EventNotPermitted do
    render status: :bad_request, json: {
      message: ['event not permitted']
    }
  end
end
