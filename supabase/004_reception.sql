-- ===========================================================================
-- 004 — Réception côté SDIS
--
-- Le SDIS saisit, dans son espace, les quantités qu'il a réellement reçues.
-- Le comptoir les voit dans une nouvelle colonne « Réceptionné », et un bon
-- dont toutes les pièces sont reçues passe au statut « réceptionné ».
--
-- Ce que fait ce script :
--   1. lignes : trois colonnes (quantité reçue, par qui, quand) ;
--   2. receptionnaires : les personnes de la réception (codes 1 à 6 pour
--      l'instant, les prénoms viendront plus tard) ;
--   3. deux fonctions, seul chemin d'écriture du compte SDIS : il ne peut
--      toucher QUE la quantité reçue, jamais le reste de la ligne ;
--   4. le journal (mouvements) trace chaque réception, avec qui et quand ;
--   5. les vues v_lignes et v_bons exposent la réception et le nouveau statut ;
--   6. reprise : tout ce qui est déjà livré passe en réceptionné.
--
-- À coller dans Supabase → SQL Editor → Run. Tout passe ou rien ne passe.
-- Annulation : 004_reception_annuler.sql
-- ===========================================================================
begin;

-- 1. Colonnes de réception ---------------------------------------------------
alter table public.lignes
  add column qte_receptionnee numeric(10,2) not null default 0,
  add column receptionne_par  text,
  add column receptionne_le   timestamptz;

alter table public.lignes
  add constraint lignes_qte_receptionnee_check check (qte_receptionnee >= 0),
  -- on ne peut pas avoir reçu plus que ce qui est parti du comptoir
  add constraint pas_plus_que_livre check (qte_receptionnee <= qte_livree);

-- 2. Personnes de la réception ----------------------------------------------
create table public.receptionnaires (
  code  text primary key,
  nom   text not null,
  actif boolean not null default true
);
insert into public.receptionnaires (code, nom) values
  ('1', '1'), ('2', '2'), ('3', '3'), ('4', '4'), ('5', '5'), ('6', '6');

alter table public.receptionnaires enable row level security;
create policy lecture_receptionnaires on public.receptionnaires for select to authenticated
  using ((select public.est_comptoir()) or (select public.est_sdis()));
revoke all on public.receptionnaires from anon, authenticated;
grant select on public.receptionnaires to authenticated;

-- 3. Écriture de la réception -------------------------------------------------
-- Le compte SDIS n'a AUCUN droit direct sur la table lignes : il passe par ces
-- deux fonctions, qui ne modifient que les colonnes de réception.
create or replace function public.receptionner(p_ligne uuid, p_qte numeric, p_qui text)
  returns void
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  if not (public.est_sdis() or public.est_comptoir()) then
    raise exception 'acces refuse' using errcode = '42501';
  end if;
  if not exists (select 1 from public.receptionnaires where nom = p_qui and actif) then
    raise exception 'receptionnaire inconnu';
  end if;
  update public.lignes
     set qte_receptionnee = p_qte,
         receptionne_par  = p_qui,
         receptionne_le   = now()
   where id = p_ligne;
  if not found then raise exception 'ligne introuvable'; end if;
end $$;

-- « Tout est arrivé » : chaque ligne du bon reçoit ce qui a été livré.
create or replace function public.receptionner_bon(p_bon uuid, p_qui text)
  returns void
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  if not (public.est_sdis() or public.est_comptoir()) then
    raise exception 'acces refuse' using errcode = '42501';
  end if;
  if not exists (select 1 from public.receptionnaires where nom = p_qui and actif) then
    raise exception 'receptionnaire inconnu';
  end if;
  update public.lignes
     set qte_receptionnee = qte_livree,
         receptionne_par  = p_qui,
         receptionne_le   = now()
   where bon_id = p_bon and qte_receptionnee < qte_livree;
end $$;

revoke execute on function public.receptionner(uuid, numeric, text) from public, anon;
revoke execute on function public.receptionner_bon(uuid, text)     from public, anon;
grant  execute on function public.receptionner(uuid, numeric, text) to authenticated;
grant  execute on function public.receptionner_bon(uuid, text)     to authenticated;

-- 4. Journal ------------------------------------------------------------------
-- Même fonction qu'avant, avec une branche de plus pour la réception. Une
-- réception seule ne touche pas modifie_le : la trace « qui / quand » affichée
-- au comptoir reste celle du dernier pointage du comptoir.
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
  if new.qte_receptionnee is distinct from old.qte_receptionnee then
    insert into mouvements (ligne_id, champ, avant, apres, operateur)
    values (new.id, 'qte_receptionnee', old.qte_receptionnee, new.qte_receptionnee, new.receptionne_par);
    if new.qte_expediee is not distinct from old.qte_expediee
       and new.qte_livree is not distinct from old.qte_livree
       and new.qte_due is not distinct from old.qte_due
       and new.reference is not distinct from old.reference then
      return new;                       -- réception seule : modifie_le inchangé
    end if;
  end if;
  new.modifie_le := now();
  return new;
end $function$;

-- 5. Vues -----------------------------------------------------------------------
-- Colonnes nouvelles ajoutées EN FIN de vue (obligatoire pour create or replace).
create or replace view public.v_lignes with (security_invoker=true) as
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
    qte_expediee - qte_livree AS qte_prepa,
    qte_receptionnee, receptionne_par, receptionne_le
   FROM lignes l;

create or replace view public.v_bons with (security_invoker=true) as
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
            WHEN count(l.id) > 0 AND COALESCE(sum(l.qte_receptionnee), 0::numeric) >= COALESCE(sum(l.qte_due), 0::numeric) THEN 'receptionne'::text
            WHEN count(l.id) > 0 AND COALESCE(sum(l.ral), 0::numeric) = 0::numeric THEN 'livre'::text
            WHEN COALESCE(sum(l.qte_livree), 0::numeric) > 0::numeric THEN 'partiel'::text
            WHEN (CURRENT_DATE - b.date_bon) > 14 THEN 'retard'::text
            WHEN (CURRENT_DATE - b.date_bon) >= 7 THEN 'surveiller'::text
            ELSE 'attente'::text
        END AS statut,
    COALESCE(sum(l.qte_receptionnee), 0::numeric) AS total_recu
   FROM bons b
     LEFT JOIN lignes l ON l.bon_id = b.id
  GROUP BY b.id;

-- 6. Reprise ----------------------------------------------------------------------
-- Choix de Joe (19/11) : ce qui était déjà livré avant la mise en service est
-- considéré comme réceptionné, signé « reprise ». Le journal est coupé le temps
-- de l'opération : pas de faux mouvements, pas de date de pointage modifiée.
alter table public.lignes disable trigger trg_trace;
update public.lignes
   set qte_receptionnee = qte_livree,
       receptionne_par  = 'reprise',
       receptionne_le   = now()
 where qte_livree > 0;
alter table public.lignes enable trigger trg_trace;

commit;
