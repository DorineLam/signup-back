class EnrollmentPolicy < ApplicationPolicy
  def create?
    record.pending?
  end

  def update?
    record.pending? && user == record.user
  end

  def delete?
    false
  end

  def send_application?
    record.can_send_application? && user == record.user
  end

  def validate_application?
    record.can_validate_application? && user.is_admin?(record.target_api)
  end

  def review_application?
    record.can_review_application? && user.is_admin?(record.target_api)
  end

  def refuse_application?
    record.can_refuse_application? && user.is_admin?(record.target_api)
  end

  def update_contacts?
    record.validated? && user == record.user
  end

  def permitted_attributes
    res = []
    if create? || send_application?
      res.concat([
        :validation_de_convention,
        :fournisseur_de_donnees,
        :linked_franceconnect_enrollment_id,
        :siret,
        contacts: [:id, :heading, :nom, :email, :phone_number],
        demarche: [
          :intitule,
          :fondement_juridique,
          :description,
          :url_fondement_juridique
        ],
        donnees: [
          :conservation,
          :destinataires,
          :rgpd_general_agreement,
          :has_alternative_authentication_methods,
          dgfip_data_years: [
            :n_moins_1,
            :n_moins_2
          ]
        ],
        documents_attributes: [
          :attachment,
          :type
        ]
      ])
    end

    if update_contacts?
      res.concat([
        contacts: [:id, :heading, :nom, :email, :phone_number],
      ])
    end

    res
  end

  class Scope < Scope
    def resolve
      %w[dgfip api_particulier franceconnect api_droits_cnam].each do |target_api|
        return scope.no_draft.send(target_api.to_sym) if user.is_admin?(target_api)
      end

      user.enrollments
    end
  end
end
