# Reporter la connexion du comptoir dans les sources

La page `site/comptoir/index.html` du dépôt a été modifiée directement. Comme elle est fabriquée par `build.py` à partir de `app.js` (et du gabarit HTML) sur le PC de Joe, il faut faire les mêmes remplacements dans ces sources, sinon le prochain build efface la connexion.

Pour chaque bloc : chercher le texte « Avant » (Ctrl+F) et le remplacer par le texte « Après ». Le bloc 4 est dans la partie HTML de la page, les autres dans le JavaScript.

## 1. Bloc CONFIG : ajouter le compte du comptoir

Avant :

```js
  cle: 'sb_publishable_fYMPaqdsK8hVW6FUXxIzNA_mhH3LvbW',
  verrouMinutes
```

Après :

```js
  cle: 'sb_publishable_fYMPaqdsK8hVW6FUXxIzNA_mhH3LvbW',
  compte: 'comptoir@sdis33pro.netlify.app',  // compte Supabase du comptoir (le mot de passe n'est PAS ici)
  verrouMinutes
```

## 2. Fonction api() : remplacée, et le bloc « Connexion du poste » ajouté juste après

Avant :

```js
function api(chemin, opts) {
  opts = opts || {};
  return fetch(CONFIG.url + '/rest/v1/' + chemin, {
    method: opts.method || 'GET',
    headers: {
      'apikey': CONFIG.cle,
      'Authorization': 'Bearer ' + CONFIG.cle,
      'Content-Type': 'application/json',
      'Prefer': opts.prefer || 'return=representation'
    },
    body: opts.body ? JSON.stringify(opts.body) : undefined
  }).then(function (r) {
    if (!r.ok) return r.text().then(function (t) { throw new Error(t || ('HTTP ' + r.status)); });
    return r.status === 204 ? null : r.json();
  });
}
```

Après :

```js
function api(chemin, opts, rejoue) {
  opts = opts || {};
  return jeton().then(function (j) {
    return fetch(CONFIG.url + '/rest/v1/' + chemin, {
      method: opts.method || 'GET',
      headers: {
        'apikey': CONFIG.cle,
        'Authorization': 'Bearer ' + j,
        'Content-Type': 'application/json',
        'Prefer': opts.prefer || 'return=representation'
      },
      body: opts.body ? JSON.stringify(opts.body) : undefined
    });
  }).then(function (r) {
    // Jeton expiré entre-temps : on le renouvelle et on rejoue une seule fois.
    if (r.status === 401 && session && !rejoue) {
      return renouveler().then(function () { return api(chemin, opts, true); });
    }
    if (!r.ok) return r.text().then(function (t) { throw new Error(t || ('HTTP ' + r.status)); });
    return r.status === 204 ? null : r.json();
  });
}

/* --------------------------------------------------------------------------
   Connexion du poste

   La base n'accepte les modifications que d'un poste connecté au compte
   « comptoir » (CONFIG.compte). Sans connexion, elle ne laisse que lire,
   comme pour l'espace client. Le mot de passe n'est écrit nulle part dans
   cette page : on le tape une fois par poste, puis la session est gardée
   dans le navigateur et renouvelée toute seule.
   -------------------------------------------------------------------------- */
var CLE_SESSION = 'sdis-comptoir-session';
var session = lireSession(), renouvellement = null;

function lireSession() {
  try { return JSON.parse(localStorage.getItem(CLE_SESSION)) || null; } catch (e) { return null; }
}
function garderSession(s) {
  session = s ? { access: s.access_token, refresh: s.refresh_token,
                  expire: Date.now() + (s.expires_in || 3600) * 1000 } : null;
  try {
    if (session) localStorage.setItem(CLE_SESSION, JSON.stringify(session));
    else localStorage.removeItem(CLE_SESSION);
  } catch (e) { /* stockage bloqué : la session ne durera que le temps de l'onglet */ }
  majPoste();
}
function auth(chemin, corps) {
  return fetch(CONFIG.url + '/auth/v1/' + chemin, {
    method: 'POST',
    headers: { 'apikey': CONFIG.cle, 'Content-Type': 'application/json' },
    body: JSON.stringify(corps)
  }).then(function (r) {
    return r.json().catch(function () { return {}; }).then(function (j) {
      if (r.ok) return j;
      var e = new Error(j.error_description || j.msg || j.message || ('HTTP ' + r.status));
      e.status = r.status; throw e;
    });
  });
}
function renouveler() {
  if (!renouvellement) {
    renouvellement = auth('token?grant_type=refresh_token', { refresh_token: session.refresh })
      .then(garderSession, function (e) {
        // Session refusée (mot de passe changé, compte désactivé) : il faudra se
        // reconnecter. Réseau coupé : on garde la session et on réessaiera.
        if (e.status >= 400 && e.status < 500) garderSession(null);
        throw e;
      })
      .then(function () { renouvellement = null; },
            function (e) { renouvellement = null; throw e; });
  }
  return renouvellement;
}
// Jeton présenté à la base : celui du poste connecté, sinon la clé publique.
function jeton() {
  if (!session) return Promise.resolve(CONFIG.cle);
  if (Date.now() < session.expire - 60000) return Promise.resolve(session.access);
  var suite = function () { return session ? session.access : CONFIG.cle; };
  return renouveler().then(suite, suite);
}
function majPoste() {
  var b = document.getElementById('poste');
  if (!b) return;
  b.textContent = session ? 'Poste connect\u00e9' : 'Connecter ce poste';
  b.classList.toggle('pri', !session);
  b.title = session ? 'Ce poste peut modifier la base. Cliquer pour le d\u00e9connecter.'
                    : 'Sans connexion, ce poste peut seulement consulter.';
}
function demanderConnexion() {
  if (document.getElementById('ov')) return;
  var ov = document.createElement('div'); ov.className = 'ov'; ov.id = 'ov';
  ov.innerHTML = '<form class="sheet" role="dialog" aria-modal="true" aria-labelledby="shT">'
    + '<h3 id="shT">Connecter ce poste</h3>'
    + '<p>Mot de passe du compte comptoir. &Agrave; faire une seule fois par poste.</p>'
    + '<input class="code" id="mdp" type="password" autocomplete="current-password" '
    + 'style="font-size:20px;letter-spacing:.08em;text-indent:0" aria-label="Mot de passe">'
    + '<p class="err" id="er"></p>'
    + '<div class="row"><button type="button" class="btn" id="cancel">Plus tard</button>'
    + '<button type="submit" class="btn pri" id="ok">Se connecter</button></div></form>';
  document.body.appendChild(ov);
  var mdp = document.getElementById('mdp'); mdp.focus();
  ov.querySelector('form').addEventListener('submit', function (e) {
    e.preventDefault();
    if (!mdp.value) return;
    var ok = document.getElementById('ok'); ok.disabled = true;
    auth('token?grant_type=password', { email: CONFIG.compte, password: mdp.value })
      .then(function (s) { garderSession(s); fermer(); erreur = null; charger(true); })
      .catch(function (e) {
        ok.disabled = false;
        document.getElementById('er').textContent = e.status === 400
          ? 'Mot de passe refus\u00e9.' : humain(e);
        mdp.classList.add('bad'); mdp.select();
        setTimeout(function () { mdp.classList.remove('bad'); }, 430);
      });
  });
  document.getElementById('cancel').addEventListener('click', fermer);
  document.addEventListener('keydown', echap);
}
function demanderDeconnexion() {
  if (document.getElementById('ov')) return;
  var ov = document.createElement('div'); ov.className = 'ov'; ov.id = 'ov';
  ov.innerHTML = '<div class="sheet" role="dialog" aria-modal="true" aria-labelledby="shT">'
    + '<h3 id="shT">D&eacute;connecter ce poste&nbsp;?</h3>'
    + '<p>Il ne pourra plus que consulter, jusqu&rsquo;&agrave; ce qu&rsquo;on retape le mot de passe.</p>'
    + '<div class="row"><button class="btn" id="cancel">Annuler</button>'
    + '<button class="btn pri" id="ok">D&eacute;connecter</button></div></div>';
  document.body.appendChild(ov);
  document.getElementById('ok').addEventListener('click', function () {
    var a = session && session.access;
    garderSession(null); fermer();
    if (a) fetch(CONFIG.url + '/auth/v1/logout', { method: 'POST',
      headers: { 'apikey': CONFIG.cle, 'Authorization': 'Bearer ' + a } }).catch(function () {});
  });
  document.getElementById('cancel').addEventListener('click', fermer);
  ov.addEventListener('click', function (e) { if (e.target === ov) fermer(); });
  document.addEventListener('keydown', echap);
}
```

## 3. Fonction humain() : message quand la base refuse faute de connexion

Avant :

```js
  if (/JWT|apikey|Invalid API key|401|403/i.test(m))
```

Après :

```js
  if (/42501|permission denied|row-level security/i.test(m)) {
    if (!session) { setTimeout(demanderConnexion, 0);
      return 'Ce poste n\'est pas connect\u00e9 : il peut consulter mais pas modifier. '
           + 'Clique sur \u00ab Connecter ce poste \u00bb.'; }
    return 'La base refuse la modification pour ce compte.';
  }
  if (/JWT|apikey|Invalid API key|401|403/i.test(m))
```

## 4. Barre du haut (partie HTML) : le bouton « Connecter ce poste », juste avant le bouton opérateur

Avant :

```html
    <button class="who" id="who">
```

Après :

```html
    <button class="btn" id="poste"></button>
    <button class="who" id="who">
```

## 5. Tout à la fin : démarrage

Avant :

```js
majQui();
charger(false);
})();
```

Après :

```js
majQui();
majPoste();
document.getElementById('poste').addEventListener('click', function () {
  if (session) demanderDeconnexion(); else demanderConnexion();
});
charger(false);
if (!session) demanderConnexion();
})();
```

## 6. Fonction charger() : la liste des opérateurs n'est lue que par un poste connecté

Avant :

```js
    Object.keys(CODES).length ? Promise.resolve(null) : api('operateurs?select=code,nom&actif=is.true')
```

Après :

```js
    // La liste des opérateurs n'est lisible que par un poste connecté.
    (!session || Object.keys(CODES).length) ? Promise.resolve(null)
      : api('operateurs?select=code,nom&actif=is.true')
```

## 7. Fonction agir() : demander la connexion avant toute modification

Avant :

```js
function agir(fn) {
  if (!moi
```

Après :

```js
function agir(fn) {
  if (!session) { demanderConnexion(); return; }   // sans connexion, la base refuserait
  if (!moi
```

## 8. Messages ajustés pour la migration 002 (lecture fermée sans connexion)

Dans la fonction `humain()` : remplacer `il peut consulter mais pas modifier. ` par `la base refuse l\'accès. `.

Dans `majPoste()` : remplacer `'Sans connexion, ce poste peut seulement consulter.'` par `'Sans connexion, la base refuse l’accès à ce poste.'`.

Dans `demanderDeconnexion()` : remplacer `Il ne pourra plus que consulter, jusqu&rsquo;&agrave; ce qu&rsquo;on retape le mot de passe.` par `Il n&rsquo;aura plus acc&egrave;s aux bons jusqu&rsquo;&agrave; ce qu&rsquo;on retape le mot de passe.`
