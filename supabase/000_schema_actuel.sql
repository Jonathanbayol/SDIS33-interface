-- =============================================================================
--  Suivi RAL SDIS 33 : schéma actuel de la base (schéma public)
--
--  Export de l'état de la base Supabase czdrfqhuamifuzznpqcq au 2026-11-19,
--  généré par lecture du catalogue PostgreSQL (lecture seule, sans données).
--
--  CE N'EST PAS UNE MIGRATION D'ORIGINE. Les scripts SQL joués à la main dans
--  l'éditeur SQL de Supabase sont perdus, et leur ordre aussi. Ce fichier
--  décrit le résultat cumulé de ces scripts, à rejouer sur une base vide.
--
--  Contenu : séquence, tables, contraintes, index, fonctions, vues,
--  déclencheurs, RLS, policies, droits des rôles anon et authenticated.
--  Les policies et droits ci-dessous sont ceux du pilote : écriture ouverte
--  à tous. Ils sont exportés tels quels, pas recommandés.
-- =============================================================================

set search_path = public;

-- -----------------------------------------------------------------------------
-- Séquence
-- -----------------------------------------------------------------------------

create sequence if not exists public.mouvements_id_seq as bigint increment by 1 minvalue 1 maxvalue 9223372036854775807 start with 1 cache 1;

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------

create table public.operateurs (
  code text not null,
  nom text not null,
  actif boolean default true not null
);

create table public.bons (
  id uuid default gen_random_uuid() not null,
  num_bon text not null,
  exercice text,
  client text,
  depot text,
  date_bon date not null,
  vreference text,
  num_commande text,
  operateur text,
  importe_le timestamp with time zone default now() not null,
  source text,
  vreference_ocr text,
  commande_ocr text,
  corrige_par text,
  corrige_le timestamp with time zone,
  heure_bon text,
  nature text default 'livraison'::text not null
);

create table public.lignes (
  id uuid default gen_random_uuid() not null,
  bon_id uuid not null,
  ordre integer default 0 not null,
  reference text not null,
  reference_ocr text,
  designation text,
  qte_due numeric(10,2) not null,
  qte_due_ocr numeric(10,2),
  qte_expediee numeric(10,2) default 0 not null,
  a_verifier boolean default false not null,
  motif text,
  appariement text,
  score numeric(4,3),
  modifie_par text,
  modifie_le timestamp with time zone,
  verifie_par text,
  verifie_le timestamp with time zone,
  reference_avant text,
  qte_livree numeric(10,2) default 0 not null,
  ral numeric(10,2) generated always as ((qte_due - qte_livree)) stored
);

create table public.mouvements (
  id bigint default nextval('mouvements_id_seq'::regclass) not null,
  ligne_id uuid not null,
  champ text not null,
  avant numeric(10,2),
  apres numeric(10,2),
  operateur text,
  au timestamp with time zone default now() not null
);

alter sequence public.mouvements_id_seq owned by public.mouvements.id;

-- -----------------------------------------------------------------------------
-- Contraintes
-- -----------------------------------------------------------------------------

alter table public.operateurs add constraint operateurs_pkey PRIMARY KEY (code);
alter table public.bons add constraint bons_pkey PRIMARY KEY (id);
alter table public.lignes add constraint lignes_pkey PRIMARY KEY (id);
alter table public.mouvements add constraint mouvements_pkey PRIMARY KEY (id);
alter table public.lignes add constraint une_reference_par_bon UNIQUE (bon_id, reference);
alter table public.operateurs add constraint operateurs_code_check CHECK ((code ~ '^[0-9]{3}$'::text));
alter table public.bons add constraint nature_connue CHECK ((nature = ANY (ARRAY['livraison'::text, 'commande'::text])));
alter table public.lignes add constraint lignes_qte_due_check CHECK ((qte_due > (0)::numeric));
alter table public.lignes add constraint lignes_qte_expediee_check CHECK ((qte_expediee >= (0)::numeric));
alter table public.lignes add constraint lignes_qte_livree_check CHECK ((qte_livree >= (0)::numeric));
alter table public.lignes add constraint pas_plus_que_du CHECK ((qte_expediee <= qte_due));
alter table public.lignes add constraint pas_plus_que_prepare CHECK ((qte_livree <= qte_expediee));
alter table public.lignes add constraint lignes_bon_id_fkey FOREIGN KEY (bon_id) REFERENCES bons(id) ON DELETE CASCADE;
alter table public.mouvements add constraint mouvements_ligne_id_fkey FOREIGN KEY (ligne_id) REFERENCES lignes(id) ON DELETE CASCADE;

-- -----------------------------------------------------------------------------
-- Index
-- -----------------------------------------------------------------------------

CREATE INDEX bons_date_bon_idx ON public.bons USING btree (date_bon DESC);
CREATE INDEX bons_vreference_idx ON public.bons USING btree (vreference);
CREATE INDEX lignes_bon_id_idx ON public.lignes USING btree (bon_id);
CREATE INDEX lignes_reference_idx ON public.lignes USING btree (reference);
CREATE INDEX lignes_a_verifier_idx ON public.lignes USING btree (a_verifier) WHERE a_verifier;
CREATE INDEX mouvements_ligne_id_au_idx ON public.mouvements USING btree (ligne_id, au DESC);
CREATE UNIQUE INDEX bons_nature_num_idx ON public.bons USING btree (nature, num_bon);

-- -----------------------------------------------------------------------------
-- Fonctions
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.trace_mouvement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.trace_entete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  if new.vreference is distinct from old.vreference then
    if new.vreference_ocr is null then
      new.vreference_ocr := old.vreference;
    end if;
    new.corrige_le := now();
  end if;
  if new.num_commande is distinct from old.num_commande then
    if new.commande_ocr is null then
      new.commande_ocr := old.num_commande;
    end if;
    new.corrige_le := now();
  end if;
  return new;
end;
$function$
;

-- -----------------------------------------------------------------------------
-- Vues
-- -----------------------------------------------------------------------------

create or replace view public.v_mouvements with (security_invoker=true) as
 SELECT m.id,
    m.au,
    m.champ,
    m.avant,
    m.apres,
    m.operateur,
    l.id AS ligne_id,
    l.bon_id,
    l.reference,
    l.designation,
    l.ordre,
    b.num_bon,
    b.exercice,
    b.vreference,
    b.nature
   FROM mouvements m
     JOIN lignes l ON l.id = m.ligne_id
     JOIN bons b ON b.id = l.bon_id;

create or replace view public.v_lignes with (security_invoker=true) as
 SELECT id,
    bon_id,
    ordre,
    reference,
    reference_ocr,
    designation,
    qte_due,
    qte_due_ocr,
    qte_expediee,
    a_verifier,
    motif,
    appariement,
    score,
    modifie_par,
    modifie_le,
    verifie_par,
    verifie_le,
    reference_avant,
    qte_livree,
    ral,
        CASE
            WHEN qte_expediee > qte_livree THEN 'prepa'::text
            WHEN ral = 0::numeric THEN 'livre'::text
            WHEN qte_livree > 0::numeric THEN 'partiel'::text
            ELSE 'attente'::text
        END AS etat,
    qte_expediee - qte_livree AS qte_prepa
   FROM lignes l;

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
            WHEN COALESCE(sum(l.ral), 0::numeric) = 0::numeric THEN 'livre'::text
            WHEN COALESCE(sum(l.qte_livree), 0::numeric) > 0::numeric THEN 'partiel'::text
            WHEN (CURRENT_DATE - b.date_bon) > 14 THEN 'retard'::text
            WHEN (CURRENT_DATE - b.date_bon) >= 7 THEN 'surveiller'::text
            ELSE 'attente'::text
        END AS statut
   FROM bons b
     LEFT JOIN lignes l ON l.bon_id = b.id
  GROUP BY b.id;

-- -----------------------------------------------------------------------------
-- Déclencheurs
-- -----------------------------------------------------------------------------

CREATE TRIGGER trg_trace BEFORE UPDATE ON lignes FOR EACH ROW EXECUTE FUNCTION trace_mouvement();
CREATE TRIGGER trg_trace_entete BEFORE UPDATE ON bons FOR EACH ROW EXECUTE FUNCTION trace_entete();

-- -----------------------------------------------------------------------------
-- Row Level Security et policies (état du pilote : tout est ouvert)
-- -----------------------------------------------------------------------------

alter table public.operateurs enable row level security;
alter table public.bons enable row level security;
alter table public.lignes enable row level security;
alter table public.mouvements enable row level security;

create policy pilote_bons on public.bons as permissive for all to public
  using (true)
  with check (true);

create policy pilote_lignes on public.lignes as permissive for all to public
  using (true)
  with check (true);

create policy pilote_mouvements on public.mouvements as permissive for all to public
  using (true)
  with check (true);

create policy pilote_operateurs on public.operateurs as permissive for select to public
  using (true);

-- -----------------------------------------------------------------------------
-- Droits des rôles Supabase (anon, authenticated)
-- -----------------------------------------------------------------------------

grant delete, insert, references, select, trigger, truncate, update on public.bons to anon;
grant delete, insert, references, select, trigger, truncate, update on public.bons to authenticated;
grant delete, insert, references, select, trigger, truncate, update on public.lignes to anon;
grant delete, insert, references, select, trigger, truncate, update on public.lignes to authenticated;
grant delete, insert, references, select, trigger, truncate, update on public.mouvements to anon;
grant delete, insert, references, select, trigger, truncate, update on public.mouvements to authenticated;
grant delete, insert, references, select, trigger, truncate, update on public.operateurs to anon;
grant delete, insert, references, select, trigger, truncate, update on public.operateurs to authenticated;
grant delete, insert, references, select, trigger, truncate, update on public.v_bons to anon;
grant delete, insert, references, select, trigger, truncate, update on public.v_bons to authenticated;
grant delete, insert, references, select, trigger, truncate, update on public.v_lignes to anon;
grant delete, insert, references, select, trigger, truncate, update on public.v_lignes to authenticated;
grant delete, insert, references, select, trigger, truncate, update on public.v_mouvements to anon;
grant delete, insert, references, select, trigger, truncate, update on public.v_mouvements to authenticated;
