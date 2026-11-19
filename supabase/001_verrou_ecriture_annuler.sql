-- =============================================================================
--  Annule 001 : revient à l'état du pilote (écriture ouverte à tous).
--  À n'utiliser qu'en dépannage, si le comptoir est bloqué.
-- =============================================================================
begin;
drop policy if exists lecture_bons on public.bons;
drop policy if exists lecture_lignes on public.lignes;
drop policy if exists lecture_mouvements on public.mouvements;
drop policy if exists lecture_operateurs on public.operateurs;
drop policy if exists comptoir_ajoute_bons on public.bons;
drop policy if exists comptoir_modifie_bons on public.bons;
drop policy if exists comptoir_supprime_bons on public.bons;
drop policy if exists comptoir_ajoute_lignes on public.lignes;
drop policy if exists comptoir_modifie_lignes on public.lignes;
drop policy if exists comptoir_supprime_lignes on public.lignes;

create policy pilote_bons on public.bons as permissive for all to public using (true) with check (true);
create policy pilote_lignes on public.lignes as permissive for all to public using (true) with check (true);
create policy pilote_mouvements on public.mouvements as permissive for all to public using (true) with check (true);
create policy pilote_operateurs on public.operateurs as permissive for select to public using (true);

grant delete, insert, references, select, trigger, truncate, update
  on public.bons, public.lignes, public.mouvements, public.operateurs,
     public.v_bons, public.v_lignes, public.v_mouvements
  to anon, authenticated;
-- est_comptoir() et les droits retirés sur les fonctions de déclencheur sont
-- laissés tels quels : ils ne gênent pas le fonctionnement ouvert.
commit;
