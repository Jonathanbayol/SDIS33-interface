-- =============================================================================
--  001 : fermer l'écriture en base au public
--
--  Avant : les policies pilote_* laissaient tout passer et le rôle anon (la
--  clé publique présente dans les deux pages) pouvait écrire partout.
--
--  Après :
--    - anon (espace client, ou poste comptoir non connecté) : lecture seule de
--      bons, lignes, mouvements et des trois vues. Plus rien sur operateurs.
--    - le compte Supabase « comptoir » (connecté depuis la page comptoir) :
--      lecture, et écriture sur bons et lignes. Les mouvements restent écrits
--      par le déclencheur trace_mouvement(), jamais directement.
--    - tout autre compte connecté : lecture seule, comme anon.
--
--  Prérequis AVANT de jouer ce script :
--    1. le compte comptoir@sdis33pro.netlify.app existe (Authentication → Users)
--    2. la page comptoir avec le bouton « Connecter ce poste » est déployée et
--       les postes sont connectés. Sinon le comptoir passe en lecture seule.
--
--  Retour arrière : 001_verrou_ecriture_annuler.sql
-- =============================================================================

begin;

-- Le compte autorisé à écrire. Une fonction plutôt que l'adresse recopiée dans
-- chaque policy : un seul endroit à changer.
create or replace function public.est_comptoir()
  returns boolean
  language sql
  stable
  set search_path = ''
as $$
  select coalesce((select auth.jwt() ->> 'email') = 'comptoir@sdis33pro.netlify.app', false)
$$;
revoke execute on function public.est_comptoir() from public, anon;
grant execute on function public.est_comptoir() to authenticated;

-- 1. Policies du pilote : supprimées --------------------------------------------
drop policy if exists pilote_bons       on public.bons;
drop policy if exists pilote_lignes     on public.lignes;
drop policy if exists pilote_mouvements on public.mouvements;
drop policy if exists pilote_operateurs on public.operateurs;

-- 2. Lecture ---------------------------------------------------------------------
create policy lecture_bons       on public.bons       for select to anon, authenticated using (true);
create policy lecture_lignes     on public.lignes     for select to anon, authenticated using (true);
create policy lecture_mouvements on public.mouvements for select to anon, authenticated using (true);
create policy lecture_operateurs on public.operateurs for select to authenticated using (true);

-- 3. Écriture : le compte comptoir seulement ------------------------------------
create policy comptoir_ajoute_bons    on public.bons for insert to authenticated with check ((select public.est_comptoir()));
create policy comptoir_modifie_bons   on public.bons for update to authenticated using ((select public.est_comptoir())) with check ((select public.est_comptoir()));
create policy comptoir_supprime_bons  on public.bons for delete to authenticated using ((select public.est_comptoir()));
create policy comptoir_ajoute_lignes   on public.lignes for insert to authenticated with check ((select public.est_comptoir()));
create policy comptoir_modifie_lignes  on public.lignes for update to authenticated using ((select public.est_comptoir())) with check ((select public.est_comptoir()));
create policy comptoir_supprime_lignes on public.lignes for delete to authenticated using ((select public.est_comptoir()));

-- 4. Droits des rôles : on repart de zéro, puis le strict nécessaire ------------
revoke all on public.bons, public.lignes, public.mouvements, public.operateurs,
              public.v_bons, public.v_lignes, public.v_mouvements
  from anon, authenticated;

grant select on public.bons, public.lignes, public.mouvements,
                public.v_bons, public.v_lignes, public.v_mouvements
  to anon, authenticated;
grant select on public.operateurs to authenticated;
grant insert, update, delete on public.bons, public.lignes to authenticated;

-- 5. Fonctions de déclencheur : pas appelables depuis l'API ---------------------
--    (un déclencheur s'exécute quand même : le droit EXECUTE n'est vérifié qu'à
--    la création du déclencheur)
revoke execute on function public.trace_mouvement() from public, anon, authenticated;
revoke execute on function public.trace_entete()    from public, anon, authenticated;
alter function public.trace_entete() set search_path = public;

commit;
