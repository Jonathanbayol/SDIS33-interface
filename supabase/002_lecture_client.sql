-- =============================================================================
--  002 : fermer aussi la lecture au public
--
--  Avant (001) : sans connexion, on pouvait encore LIRE bons, lignes et
--  mouvements avec la clé publique. Le code 30258 n'était vérifié que dans
--  la page.
--
--  Après :
--    - sans connexion : plus rien, ni lecture ni écriture.
--    - compte client « barrault-interface@sdis33.fr » (espace client) : lecture
--      des bons, lignes et mouvements.
--    - compte « comptoir@sdis33pro.netlify.app » : lecture et écriture, comme
--      avec 001, plus la liste des opérateurs.
--    - tout autre compte connecté : rien.
--
--  Prérequis AVANT de jouer ce script :
--    1. le compte barrault-interface@sdis33.fr existe (Authentication → Users)
--    2. la nouvelle page client (avec mot de passe) est en ligne
--    3. les postes du comptoir sont connectés (sinon ils ne voient plus rien)
--
--  Retour arrière : 002_lecture_client_annuler.sql (revient à l'état 001)
-- =============================================================================

begin;

create or replace function public.est_sdis()
  returns boolean
  language sql
  stable
  set search_path = ''
as $$
  select coalesce((select auth.jwt() ->> 'email') = 'barrault-interface@sdis33.fr', false)
$$;
revoke execute on function public.est_sdis() from public, anon;
grant execute on function public.est_sdis() to authenticated;

-- Lecture : compte comptoir ou compte client seulement
drop policy if exists lecture_bons       on public.bons;
drop policy if exists lecture_lignes     on public.lignes;
drop policy if exists lecture_mouvements on public.mouvements;
drop policy if exists lecture_operateurs on public.operateurs;

create policy lecture_bons       on public.bons       for select to authenticated
  using ((select public.est_comptoir()) or (select public.est_sdis()));
create policy lecture_lignes     on public.lignes     for select to authenticated
  using ((select public.est_comptoir()) or (select public.est_sdis()));
create policy lecture_mouvements on public.mouvements for select to authenticated
  using ((select public.est_comptoir()) or (select public.est_sdis()));
create policy lecture_operateurs on public.operateurs for select to authenticated
  using ((select public.est_comptoir()));

-- Plus aucun droit pour la clé publique seule
revoke all on public.bons, public.lignes, public.mouvements, public.operateurs,
              public.v_bons, public.v_lignes, public.v_mouvements
  from anon;

commit;
