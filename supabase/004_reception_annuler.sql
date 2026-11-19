-- ===========================================================================
-- Annule 004_reception.sql. Les quantités réceptionnées sont PERDUES.
-- Remet les vues et le journal exactement comme après 003.
-- ===========================================================================
begin;

drop function if exists public.receptionner(uuid, numeric, text);
drop function if exists public.receptionner_bon(uuid, text);

-- Les vues dépendent des nouvelles colonnes : on les recrée sans elles.
drop view public.v_bons;
drop view public.v_lignes;

create view public.v_lignes with (security_invoker=true) as
 SELECT id, bon_id, ordre, reference, reference_ocr, designation,
    qte_due, qte_due_ocr, qte_expediee, a_verifier, motif, appariement, score,
    modifie_par, modifie_le, verifie_par, verifie_le, reference_avant,
    qte_livree, ral,
        CASE
            WHEN qte_expediee > qte_livree THEN 'prepa'::text
            WHEN ral = 0::numeric THEN 'livre'::text
            WHEN qte_livree > 0::numeric THEN 'partiel'::text
            ELSE 'attente'::text
        END AS etat,
    qte_expediee - qte_livree AS qte_prepa
   FROM lignes l;

create view public.v_bons with (security_invoker=true) as
 SELECT b.id, b.num_bon, b.exercice, b.client, b.depot, b.date_bon, b.vreference,
    b.num_commande, b.operateur, b.importe_le, b.source, b.vreference_ocr,
    b.commande_ocr, b.corrige_par, b.corrige_le, b.heure_bon, b.nature,
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

grant select on public.v_bons, public.v_lignes to authenticated;

-- Journal : version d'avant 004.
create or replace function public.trace_mouvement()
  returns trigger
  language plpgsql
  security definer
  set search_path to 'public'
as $function$
begin
  if new.qte_expediee is distinct from old.qte_expediee then
    insert into mouvements (ligne_id, champ, avant, apres, operateur)
    values (new.id, 'qte_expediee', old.qte_expediee, new.qte_expediee, new.modifie_par);
  end if;
  if new.qte_livree is distinct from old.qte_livree then
    insert into mouvements (ligne_id, champ, avant, apres, operateur)
    values (new.id, 'qte_livree', old.qte_livree, new.qte_livree, new.modifie_par);
  end if;
  if new.qte_due is distinct from old.qte_due then
    if new.qte_due_ocr is null then
      new.qte_due_ocr := old.qte_due;
    end if;
    insert into mouvements (ligne_id, champ, avant, apres, operateur)
    values (new.id, 'qte_due', old.qte_due, new.qte_due, new.modifie_par);
  end if;
  if new.reference is distinct from old.reference then
    if new.reference_avant is null then
      new.reference_avant := old.reference;
    end if;
    insert into mouvements (ligne_id, champ, avant, apres, operateur)
    values (new.id, 'reference', null, null, new.modifie_par);
  end if;
  if new.verifie_par is distinct from old.verifie_par and new.verifie_par is not null then
    new.verifie_le  := now();
    new.a_verifier  := false;
  end if;
  new.modifie_le := now();
  return new;
end $function$;
revoke execute on function public.trace_mouvement() from public, anon, authenticated;

delete from public.mouvements where champ = 'qte_receptionnee';
drop table public.receptionnaires;
alter table public.lignes
  drop constraint pas_plus_que_livre,
  drop constraint lignes_qte_receptionnee_check,
  drop column qte_receptionnee,
  drop column receptionne_par,
  drop column receptionne_le;

commit;
