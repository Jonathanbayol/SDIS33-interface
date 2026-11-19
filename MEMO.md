# Suivi RAL — SDIS 33 / Barrault Le Haillan

Mémo de projet. Écrit pour qu'une session Claude qui n'a jamais vu ce dossier
puisse reprendre le travail sans tout redemander.

---

## 1. Le problème qu'on résout

Barrault Le Haillan (pièces automobiles) livre le SDIS 33 — les pompiers de
Gironde, code client **30258**. Le suivi du **RAL** (reste à livrer) se faisait
sur des liasses papier que cinq personnes se passaient au comptoir. Personne ne
savait dire à l'instant T ce qui restait dû au client, et le SDIS relançait sur
sa propre référence (V/référence, format `T3263405`) que personne ne retrouvait.

L'outil remplace ces liasses. Il tient ce qui est commandé, ce qui est préparé,
ce qui est livré, et il imprime le bon remis au client.

Adresse du client sur les documents :
SDIS 33 · 22 BOULEVARD PIERRE 1ER · 33081 BORDEAUX · FRANCE

---

## 2. Ce qui existe aujourd'hui

**Trois morceaux, trois endroits.**

| Quoi | Où | Forme |
|---|---|---|
| Base de données | Supabase, projet `czdrfqhuamifuzznpqcq` (eu) | PostgreSQL + PostgREST |
| Outil du comptoir | Netlify, site n°1 | `index.html`, un seul fichier |
| Espace client SDIS | Netlify, site n°2 | `client.html` déployé sous le nom `index.html` |
| Lecteur de scans | PC de Joe, dossier d'installation | Python + `.bat` |

Les deux pages sont **autonomes** : tout est embarqué dedans (CSS, JS, logo et
bandeau en base64). Aucune dépendance extérieure, aucun build côté serveur. Le
bloc `CONFIG` en tête de chaque fichier porte l'URL Supabase et la clé publique.

Le lecteur de scans contient `importer.py`, `extraction.py`, `lecture_ia.py`,
`config.ini` (clé API, **jamais** dans les zips), `import.bat`,
`import-simulation.bat`, et un dossier `scans/` où tombent les PDF.

### Chaîne de montage des pages

Les deux HTML sont assemblés par script, à partir de sources séparées :

- `build.py` → `index.html` = squelette + catalogue (318 réf.) + bandeau + `app.js`
- `build-client.py` → `client.html` = `client-head.html` + logo + bandeau + `client.js`

Si on modifie le HTML final sans toucher la source, le prochain build écrase
la modification.

---

## 3. Le modèle de données

**`bons`** — un document reçu du magasin.
`num_bon`, `exercice`, `client`, `depot`, `date_bon`, `heure_bon`,
`vreference` (la référence du SDIS), `num_commande`, `operateur`, `nature`,
`source`, plus les colonnes de correction manuelle (`vreference_ocr`,
`commande_ocr`, `corrige_par`, `corrige_le`).

Unicité : **(`nature`, `num_bon`)**, pas le numéro seul — les deux séries de
numéros peuvent se croiser.

**`lignes`** — une référence pièce sur un bon.
`bon_id`, `ordre`, `reference`, `designation`,
`qte_due`, `qte_expediee`, `qte_livree`, `ral` (colonne générée),
`a_verifier`, `motif`, `reference_ocr`, `qte_due_ocr`, `verifie_par`.

**`mouvements`** — l'historique, alimenté par le trigger `trace_mouvement()`.

**Vues** : `v_bons`, `v_lignes`, `v_mouvements`, toutes en `security_invoker`
avec `grant select to anon, authenticated`. `v_bons` agrège les lignes et
calcule l'ancienneté et le statut.

---

## 4. Le mécanisme central — préparer, puis livrer

C'est le cœur du système, et la source de la plupart des décisions.

1. L'opérateur pointe les quantités avec `+` / `−` → ça remplit
   **`qte_expediee`**. La pièce est sur l'étagère, elle n'est **pas** livrée.
   La ligne passe « En préparation ».
2. Il clique **Imprimer**. Une fenêtre liste ce qui va être déclaré livré.
3. À la confirmation, `qte_livree = qte_expediee`, **puis** le bon s'imprime.
4. Si l'écriture en base échoue, **rien n'est imprimé** : on ne remet jamais au
   client un papier que la base ne confirme pas.

`ral = qte_due − qte_livree`. Une pièce préparée mais pas partie reste due.

**États** d'une ligne et d'un bon : En attente · En préparation · Livré
partiellement · Livré, plus À surveiller (J+7) et En retard (J+14) selon l'âge.
Le mot **« soldé » est banni** de l'interface.

Dans l'interface, le préparé est **bleu**, le livré est **vert**. La jauge de
chaque bon porte les deux niveaux.

---

## 5. Deux documents, une seule mécanique — BL et CMD

Le magasin traite la demande du client sous deux formes :

- **BL** (bon de livraison) — facturé. Code-barres de **15 chiffres** :
  n° (7) + dépôt (2) + AAMMJJ. Deux colonnes de quantité, `Qt cmdée` et
  `Qt livrée` ; on ne retient que la seconde.
- **CMD** (commande) — pas encore facturé. Code-barres de **9 chiffres** :
  n° (7) + dépôt (2), sans date. Une seule colonne `Quantité`.

**Pour le suivi du RAL, les deux disent exactement la même chose.** Rien ne
change dans les calculs : seule l'étiquette affichée diffère. La nature est
écrite en base à l'import, d'après le code-barres — jamais déduite de la
longueur du numéro, règle qui tomberait le jour où les séries changent. Une
saisie manuelle n'a pas de code-barres : le formulaire demande BL ou CMD.

---

## 6. Le bon de livraison imprimé

Fidèle au devis Barrault : même bandeau, mêmes cases grises, mêmes colonnes,
positions absolues en points mesurées sur le PDF d'origine.

- Titre « BON DE LIVRAISON N° », code-barres Code39 recomposé.
- Cases : Date, Heure, Client, Opérateur, Dépôt, Page.
  **Date et heure sont celles de l'impression**, pas celles du bon.
  **L'opérateur est celui qui imprime**, pas celui qui a créé le bon.
- Colonnes : Référence · Désignation · Qt cmd · Quantité.
- **Trois sections**, séparées par un blanc :
  `RÉFÉRENCES LIVRÉES PAR CE BON` · `RÉFÉRENCES DÉJÀ LIVRÉES` (absente si vide)
  · `RÉFÉRENCES RESTANT À LIVRER`.
  Une même référence peut figurer dans plusieurs sections avec des quantités
  différentes. La colonne Qt cmd permet de recouper :
  livré ce jour + déjà livré + reste = quantité commandée.
- **Cadre « Tampon et signature du client »** en bas à droite, dernière page
  seulement.
- Pagination avec en-tête réimprimé et mention « (suite) ».

L'espace client dispose d'un second document imprimable, le **récapitulatif des
articles en attente**, au même format.

---

## 7. Le lecteur de scans

Les PDF scannés tombent dans `scans/`. `import.bat` les lit et les envoie en
base ; `import-simulation.bat` fait tout sauf écrire.

- **Les codes-barres sont lus en local** (zxing-cpp) : numéro, dépôt, date,
  code client, avec une fiabilité de 100 % et gratuitement. Le code-barres
  d'une commande étant imprimé plus fin, le lecteur réessaie en agrandissant
  puis en seuillant quand la première passe échoue.
- **Le tableau des articles est lu par l'API Claude** (modèle vision, ~0,4
  centime la page). Le modèle rend aussi la V/référence, le n° de commande,
  la date, l'heure, l'opérateur, et signale chaque ligne douteuse.
- **Repli Tesseract** si la clé API manque ou l'API est injoignable — et il dit
  pourquoi, explicitement.
- Une page sans numéro de bon n'est plus jetée en silence : le lecteur affiche
  laquelle et pourquoi.
- Les fichiers traités partent dans `scans/traites`.

La clé API vit dans `config.ini`, section `[claude]`. **Ce fichier n'est jamais
remplacé par les livraisons de code.**

---

## 8. Design

Fond anthracite, camaïeu de bleu, effet verre sur la barre du haut et les
fenêtres. Hiérarchie par les graisses, H1 à H4 maximum. Bouton de thème
clair/sombre sur les deux interfaces, choix mémorisé par poste
(`localStorage`, clé `sdis-theme`), et un script anti-flash dans le `<head>`.

Trois durées d'animation : 140 ms (clic), 220 ms (état), 340 ms (bloc).

**Contrastes calculés, jamais estimés** : texte principal 16,6:1, secondaire
7,7:1, blanc sur bleu 4,8:1.

Règle de Joe : tout bouton ou badge coloré prend un **aplat de couleur pleine
avec texte blanc**, pas un fond pâle avec texte coloré.

Une compétence Claude enregistrée, **`design-outil-metier`**, porte ces règles.

---

## 9. Pièges rencontrés — à ne pas refaire

- **Jamais de remplacement approximatif** dans ces gros fichiers HTML d'un seul
  tenant. Une recherche de `/* ==========` a déjà détruit `index.html`. On
  utilise des ancres exactes avec `assert count == 1`.
- **Toute classe émise par le JS doit avoir une règle CSS.** Des boutons
  invisibles sont partis en production parce qu'une classe passée en argument
  n'avait pas de style.
- **À l'impression**, `color-scheme:dark` fait peindre les marges en noir →
  `:root{color-scheme:light}` dans `@media print`.
- **Le dégradé de fond du thème** est posé avec `!important` sur un sélecteur
  plus spécifique que `body`. Une règle d'impression simple perd : il faut
  `:root:root:root body`, sinon le bleu part à l'imprimante.
- **Code39** : start/stop `nwnnwnwnn`, et 10 modules de silence obligatoires de
  chaque côté. Vérifié par décodage aller-retour.
- **Un bloc `do $$`** dans l'éditeur SQL de Supabase ne voit pas toujours le
  schéma `public`. Préférer des instructions simples, idempotentes.
- **PostgreSQL n'indexe pas les clés étrangères** automatiquement.
- **Vérifier, pas estimer** : les hauteurs de ligne du bon imprimé sont
  mesurées en mode impression avec Playwright, les contrastes sont calculés,
  les migrations SQL sont rejouées sur un PostgreSQL vide avant livraison.

---

## 10. Ce qui reste ouvert

**Urgent — sécurité, avant de donner l'adresse au SDIS.**
L'espace client est une page publique : le code 30258 et la clé Supabase sont
lisibles dans son code source, et **cette clé autorise encore l'écriture sur
toutes les tables**. La page ne fait que lire, mais quelqu'un qui recopie la
clé pourrait modifier des quantités. Il faut verrouiller les droits côté base
— les codes opérateur deviennent de vrais comptes, le côté client passe en
lecture seule au niveau du serveur — **avant** de communiquer l'adresse.

**Performance.** Erreurs 504 sur `v_bons?select=*` et `v_lignes?select=*` :
la base ne répond plus à temps. Deux pistes, dans l'ordre : créer l'index
`lignes(bon_id)` qui manque probablement, puis arrêter de recharger toutes les
données toutes les 25 secondes sur cinq postes.

**Bogue connu.** Un bon sans aucune ligne s'affiche « Livré », parce que son
reste à livrer vaut zéro. Un bon vide n'est pas livré, il est vide.

**Question en suspens.** Un bon dont la marchandise est prête affiche « En
préparation » même s'il attend depuis trois semaines : l'état masque l'âge.
Faut-il que « En retard » reprenne le dessus ?

**Chantier en cours.** Un flux Power Automate pour récupérer les scans depuis
un dossier SharePoint. Attention au conflit de rangement : si la
synchronisation redescend les fichiers que le script vient d'archiver, ça
tourne en rond. Il faut décider qui range.

**Plus tard.** Un rapport RAL envoyé par mail au client.

---

## 11. Comment travailler sur ce projet

Joe veut du direct, du concis, et des étapes séquencées. Pas de flatterie.
On parle français.

Les sessions Claude perdent leur espace de travail entre deux conversations :
**il faut lui redemander les fichiers avant de les modifier**, et ne jamais les
reconstruire de mémoire. La source de vérité, c'est ce qui tourne sur Netlify —
récupérable depuis le dashboard, Deploys → le dernier déploiement → Download.

Toute modification se vérifie avant d'être livrée : Playwright pour les
interfaces et le PDF imprimé, un PostgreSQL de test pour les migrations,
zéro erreur console dans les deux thèmes.
