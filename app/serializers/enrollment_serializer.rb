class EnrollmentSerializer < ActiveModel::Serializer
  attributes :updated_at, :created_at, :id, :target_api, :previous_enrollment_id, :copied_from_enrollment_id,
    :cgu_approved, :scopes, :contacts, :organization_id, :siret, :nom_raison_sociale, :status, :linked_token_manager_id,
    :additional_content, :intitule, :description, :fondement_juridique_title, :fondement_juridique_url,
    :data_recipients, :data_retention_period, :data_retention_comment, :dpo_label, :dpo_email, :dpo_phone_number,
    :responsable_traitement_label, :responsable_traitement_email, :responsable_traitement_phone_number, :demarche

  belongs_to :user, serializer: UserWithProfileSerializer

  has_many :documents
  has_many :events

  attribute :acl do
    Hash[
      EnrollmentPolicy.acl_methods.map { |method|
        [method.to_s.delete("?"), EnrollmentPolicy.new(current_user, object).send(method)]
      }
    ]
  end
end
