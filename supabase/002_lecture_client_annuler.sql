-- =============================================================================
--  Annule 002 : la lecture redevient possible sans connexion (état 001).
--  L'écriture reste réservée au compte comptoir.
-- =============================================================================
begin;
drop policy if exists lecture_bons       on public.bons;
drop policy if exists lecture_lignes     on public.lignes;
drop policy if exists lecture_mouvements on public.mouvements;
drop policy if exists lecture_operateurs on public.operateurs;
create policy lecture_bons       on public.bons       for select to anon, authenticated using (true);
create policy lecture_lignes     on public.lignes     for select to anon, authenticated using (true);
create policy lecture_mouvements on public.mouvements for select to anon, authenticated using (true);
create policy lecture_operateurs on public.operateurs for select to authenticated using (true);
grant select on public.bons, public.lignes, public.mouvements,
                public.v_bons, public.v_lignes, public.v_mouvements
  to anon;
commit;
