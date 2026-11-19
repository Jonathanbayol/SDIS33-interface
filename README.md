# Suivi RAL — SDIS 33 / Barrault Le Haillan

Outil de suivi des **restes à livrer (RAL)** du client SDIS 33 (code client
30258) chez Barrault Le Haillan. Il remplace les liasses papier du comptoir :
il tient ce qui est commandé, ce qui est préparé, ce qui est livré, et il
imprime le bon remis au client. Les bons sont saisis à la main au comptoir.

Le détail du modèle de données, du mécanisme préparer / livrer et des
décisions est dans [`docs/MEMO.md`](docs/MEMO.md).

> **Dépôt privé — ne pas le rendre public.**
> Les deux HTML contiennent l'URL Supabase, la clé publique et le code d'accès
> client. Cette clé autorise encore l'écriture sur toutes les tables (voir
> « État de la base » plus bas). Tant que les droits ne sont pas verrouillés
> côté Supabase, ni ce dépôt ni l'adresse de l'espace client ne doivent être
> communiqués.

---

## Contenu du dépôt

| Chemin | Rôle |
|---|---|
| `site/comptoir/index.html` | Outil du comptoir : saisie, pointage, impression du bon de livraison |
| `site/client/index.html` | Espace client SDIS : consultation, récapitulatif des articles en attente |
| `supabase/000_schema_actuel.sql` | Schéma actuel de la base (export du 2026-11-19, voir plus bas) |
| `docs/MEMO.md` | Mémo de projet |

Les deux pages sont **autonomes** : CSS, JS, logo et bandeau sont embarqués
dans le fichier. Aucun build côté serveur. Le bloc `CONFIG` en tête de chaque
fichier porte l'URL Supabase et la clé publique.

---

## Où chaque morceau est déployé

| Morceau | Déploiement |
|---|---|
| Base de données | Supabase, projet `czdrfqhuamifuzznpqcq` (région eu) |
| Outil du comptoir | Netlify — https://sdis33pro.netlify.app/ |
| Espace client SDIS | Netlify — https://sdis33.netlify.app/ |

Les deux sites Netlify sont publiés par glisser-déposer (Deploys → Drag and
drop), pas depuis ce dépôt. Chaque site reçoit un dossier contenant un seul
`index.html`.

**Source de vérité : ce qui tourne sur Netlify.** Les HTML de ce dépôt sont
ceux des derniers déploiements au 2026-11-19. Pour resynchroniser : Deploys →
dernier déploiement → Download, remplacer le fichier dans `site/`, commiter.

---

## Migrations SQL — ordre d'exécution

**Les migrations d'origine et leur ordre sont perdus.** Les scripts ont été
joués à la main dans Supabase → SQL Editor, qui n'en garde aucune trace
(l'historique des migrations du projet est vide), et les fichiers n'ont pas
été conservés.

À la place, `supabase/000_schema_actuel.sql` est un **export de l'état de la
base au 2026-11-19**, lu dans le catalogue PostgreSQL, sans données : tables,
contraintes, index, fonctions, vues, déclencheurs, RLS, policies, droits des
rôles `anon` et `authenticated`.

Vérifications faites le 2026-11-19 :
- le fichier se rejoue sans erreur sur un PostgreSQL 16 vide (avec les rôles
  `anon` et `authenticated` créés au préalable) ;
- la base rejouée et la base Supabase ont la même empreinte de schéma
  (166 objets comparés : colonnes, contraintes, index, fonctions, vues,
  déclencheurs, RLS, policies, droits).

Toute nouvelle migration s'ajoute à côté, numérotée à la suite
(`001_…sql`, `002_…sql`), et se joue après `000`.

---

## État de la base constaté à l'export

- **Écriture ouverte.** Les policies `pilote_*` autorisent tout
  (`using (true) with check (true)`) sur `bons`, `lignes` et `mouvements`, et
  `anon` a tous les droits sur les tables et les vues. C'est le verrou à poser
  avant de communiquer l'espace client.
  → Corrigé par `supabase/001_verrou_ecriture.sql` (lecture seule pour
  `anon`, écriture réservée au compte Supabase `comptoir@sdis33pro.netlify.app`,
  connecté depuis la page comptoir). Retour arrière :
  `001_verrou_ecriture_annuler.sql`. Report dans les sources du build :
  `docs/connexion-comptoir-sources.md`.
- **L'index `lignes(bon_id)` existe déjà** (`lignes_bon_id_idx`). La première
  piste du mémo contre les erreurs 504 est donc écartée ; reste la seconde,
  le rechargement complet toutes les 25 secondes.
- **Bon vide affiché « Livré » :** confirmé dans `v_bons`, le statut passe à
  `livre` quand la somme des RAL vaut 0, y compris sans aucune ligne.
- `trace_entete()` est `security definer` sans `search_path` fixé, à la
  différence de `trace_mouvement()`.

---

## Hors dépôt

- **Sources du build des pages.** Les HTML sont assemblés par `build.py` et
  `build-client.py` à partir de sources séparées (`app.js`, `client.js`,
  `client-head.html`, catalogue), restées sur le PC de Joe. Une modification
  faite directement dans `site/*/index.html` sera écrasée au prochain build si
  la source n'est pas modifiée aussi.
- **Lecteur de scans : abandonné.** Les bons sont désormais saisis à la main.
