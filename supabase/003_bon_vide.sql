-- =============================================================================
--  003 : un bon sans aucune ligne n'est plus affiché « Livré »
--
--  Avant : dans v_bons, le statut passait à « livre » dès que la somme des
--  restes à livrer valait 0... ce qui est aussi le cas d'un bon qui n'a
--  aucune ligne (somme vide = 0).
--  Après : il faut au moins une ligne pour être « livre ». Un bon vide suit
--  la règle des bons en attente : « attente », puis « surveiller » à 7 jours
--  et « retard » au-delà de 14 jours, pour qu'il saute aux yeux et qu'on le
--  complète ou le supprime.
--
--  Seule la ligne « livre » du CASE change. Les droits sur la vue sont
--  conservés (create or replace view).
--  Retour arrière : 003_bon_vide_annuler.sql
-- =============================================================================

create or replace view public.v_bons with (security_invoker=true) as
 SELECT b.id,
    b.num_bon,
    b.exercice,
    b.client,
    b.depot,
    b.date_bon,
    b.vreference,
    b.num_commande,
    b.operateur,
    b.importe_le,
    b.source,
    b.vreference_ocr,
    b.commande_ocr,
    b.corrige_par,
    b.corrige_le,
    b.heure_bon,
    b.nature,
    CURRENT_DATE - b.date_bon AS anciennete,
    count(l.id) AS nb_lignes,
    COALESCE(sum(l.ral), 0::numeric) AS ral_pieces,
    count(l.id) FILTER (WHERE l.ral > 0::numeric) AS ral_lignes,
    count(l.id) FILTER (WHERE l.a_verifier) AS nb_a_verifier,
    COALESCE(sum(l.qte_due), 0::numeric) AS total_du,
    COALESCE(sum(l.qte_expediee), 0::numeric) AS total_expedie,
    COALESCE(sum(l.qte_livree), 0::numeric) AS total_livre,
    COALESCE(sum(l.qte_expediee - l.qte_livree), 0::numeric) AS total_prepa,
        CASE
            WHEN COALESCE(sum(l.qte_expediee - l.qte_livree), 0::numeric) > 0::numeric THEN 'prepa'::text
            WHEN count(l.id) > 0 AND COALESCE(sum(l.ral), 0::numeric) = 0::numeric THEN 'livre'::text
            WHEN COALESCE(sum(l.qte_livree), 0::numeric) > 0::numeric THEN 'partiel'::text
            WHEN (CURRENT_DATE - b.date_bon) > 14 THEN 'retard'::text
            WHEN (CURRENT_DATE - b.date_bon) >= 7 THEN 'surveiller'::text
            ELSE 'attente'::text
        END AS statut
   FROM bons b
     LEFT JOIN lignes l ON l.bon_id = b.id
  GROUP BY b.id;
