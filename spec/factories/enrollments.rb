# frozen_string_literal: true

FactoryGirl.define do
  factory :enrollment do
    fournisseur_de_service 'test'
    description_service "test"
    validation_de_convention true
  end

  factory :sent_enrollment, class: 'Enrollment' do
    fournisseur_de_service "test"
    description_service "test"
    fondement_juridique "test"
    scope_dgfip_avis_imposition true
    scope_cnaf_attestation_droits true
    scope_cnaf_quotient_familial true
    nombre_demandes_annuelle 34568
    pic_demandes_par_heure 567
    nombre_demandes_mensuelles_jan 45
    nombre_demandes_mensuelles_fev 45
    nombre_demandes_mensuelles_mar 45
    nombre_demandes_mensuelles_avr 45
    nombre_demandes_mensuelles_mai 45
    nombre_demandes_mensuelles_jui 45
    nombre_demandes_mensuelles_jul 45
    nombre_demandes_mensuelles_aou 45
    nombre_demandes_mensuelles_sep 45
    nombre_demandes_mensuelles_oct 45
    nombre_demandes_mensuelles_nov 45
    nombre_demandes_mensuelles_dec 45
    autorite_certification_nom "test"
    autorite_certification_fonction "test"
    date_homologation "2018-06-01"
    date_fin_homologation "2019-06-01"
    delegue_protection_donnees "test"
    validation_de_convention true
    certificat_pub_production "test"
    autorite_certification "test"
    state 'sent'
  end
end
