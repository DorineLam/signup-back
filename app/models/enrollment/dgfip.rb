class Enrollment::Dgfip < Enrollment
  resourcify

  def as_json(*params)
    super(*params).merge({
      'autorite_certification' => autorite_certification,
      'ips_de_production' => ips_de_production,
      'autorite_homologation_nom' => autorite_homologation_nom,
      'autorite_homologation_fonction' => autorite_homologation_fonction,
      'date_homologation' => date_homologation,
      'date_fin_homologation' => date_fin_homologation,
      'nombre_demandes_annuelle' => nombre_demandes_annuelle,
      'pic_demandes_par_seconde' => pic_demandes_par_seconde,
      'nombre_demandes_mensuelles_jan' => nombre_demandes_mensuelles_jan,
      'nombre_demandes_mensuelles_fev' => nombre_demandes_mensuelles_fev,
      'nombre_demandes_mensuelles_mar' => nombre_demandes_mensuelles_mar,
      'nombre_demandes_mensuelles_avr' => nombre_demandes_mensuelles_avr,
      'nombre_demandes_mensuelles_mai' => nombre_demandes_mensuelles_mai,
      'nombre_demandes_mensuelles_jui' => nombre_demandes_mensuelles_jui,
      'nombre_demandes_mensuelles_jul' => nombre_demandes_mensuelles_jul,
      'nombre_demandes_mensuelles_aou' => nombre_demandes_mensuelles_aou,
      'nombre_demandes_mensuelles_sep' => nombre_demandes_mensuelles_sep,
      'nombre_demandes_mensuelles_oct' => nombre_demandes_mensuelles_oct,
      'nombre_demandes_mensuelles_nov' => nombre_demandes_mensuelles_nov,
      'nombre_demandes_mensuelles_dec' => nombre_demandes_mensuelles_dec,
      'recette_fonctionnelle' => recette_fonctionnelle
    })
  end

  protected

  def sent_validation
    super
    errors[:ips_de_production] << "Vous devez renseigner les IP(s) de production avant de continuer" unless ips_de_production.present?
    errors[:recette_fonctionnelle] << "Vous devez attester avoir réaliser une recette fonctionnelle avant de continuer" unless recette_fonctionnelle?
  end
end
