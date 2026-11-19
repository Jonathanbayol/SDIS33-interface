# Reporter la connexion de l'espace client dans les sources

Même principe que `connexion-comptoir-sources.md`, pour `client.js` et `client-head.html` (fabriqués par `build-client.py`). Chercher le texte « Avant », le remplacer par « Après ».

## 1. Bloc CONFIG : le code d'accès remplacé par le compte client

Avant :

```js
  code: '30258',            // le n° de client SDIS sert de code d'accès
```

Après :

```js
  compte: 'sdis@sdis33pro.netlify.app',  // compte Supabase du client (le mot de passe n'est PAS ici)
```

## 2. Commentaire d'en-tête

Avant :

```js
   Cette page ne fait que LIRE.
```

Après :

```js
   Cette page ne fait que LIRE, et seulement une fois connectée au compte
   Supabase du client (CONFIG.compte) : la base refuse toute lecture sans
   connexion.
```

## 3. Fonction api() : remplacée, et la gestion de session ajoutée juste après

Avant :

```js
function api(chemin) {
  return fetch(CONFIG.url + '/rest/v1/' + chemin, {
    method: 'GET',
    headers: {
      'apikey': CONFIG.cle,
      'Authorization': 'Bearer ' + CONFIG.cle,
      'Content-Type': 'application/json'
    }
  }).then(function (r) {
    if (!r.ok) return r.text().then(function (t) { throw new Error(t || ('HTTP ' + r.status)); });
    return r.json();
  });
}
```

Après :

```js
function api(chemin, rejoue) {
  return jeton().then(function (j) {
    return fetch(CONFIG.url + '/rest/v1/' + chemin, {
      method: 'GET',
      headers: {
        'apikey': CONFIG.cle,
        'Authorization': 'Bearer ' + j,
        'Content-Type': 'application/json'
      }
    });
  }).then(function (r) {
    // Jeton expiré entre-temps : on le renouvelle et on rejoue une seule fois.
    if (r.status === 401 && session && !rejoue) {
      return renouveler().then(function () { return api(chemin, true); });
    }
    if (!r.ok) return r.text().then(function (t) { throw new Error(t || ('HTTP ' + r.status)); });
    return r.json();
  });
}

/* Session du compte client : gardée dans le navigateur et renouvelée seule,
   pour ne pas redemander le mot de passe à chaque visite. */
var CLE_SESSION = 'sdis-client-session';
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
        // Session refusée (mot de passe changé) : retour à l'écran de connexion.
        // Réseau coupé : on garde la session et on réessaiera.
        if (e.status >= 400 && e.status < 500) { garderSession(null); location.reload(); }
        throw e;
      })
      .then(function () { renouvellement = null; },
            function (e) { renouvellement = null; throw e; });
  }
  return renouvellement;
}
function jeton() {
  if (!session) return Promise.resolve(CONFIG.cle);
  if (Date.now() < session.expire - 60000) return Promise.resolve(session.access);
  var suite = function () { return session ? session.access : CONFIG.cle; };
  return renouveler().then(suite, suite);
}
```

## 4. Commentaire « Connexion »

Avant :

```js
   Le code n'est qu'une porte : il évite qu'une adresse tombée par hasard
   affiche les livraisons. Il ne protège pas la base — c'est le rôle des
   droits côté serveur.
```

Après :

```js
   Le mot de passe est vérifié par Supabase, pas par la page : sans
   connexion au compte client, la base ne renvoie rien.
```

## 5. Validation de l'écran d'entrée : vérification par Supabase

Avant :

```js
  var champ = document.getElementById('mdp'), err = document.getElementById('err');
  if (champ.value.trim() === CONFIG.code) {
    memoire('sdis-ouvert', '1');
    ouvrir();
  } else {
    err.textContent = 'Code incorrect.';
    champ.classList.add('faux');
    champ.select();
    setTimeout(function () { champ.classList.remove('faux'); }, 450);
  }
});
```

Après :

```js
  var champ = document.getElementById('mdp'), err = document.getElementById('err');
  var bouton = this.querySelector('button[type=submit]');
  if (!champ.value) return;
  bouton.disabled = true; err.textContent = '';
  auth('token?grant_type=password', { email: CONFIG.compte, password: champ.value })
    .then(function (s) { garderSession(s); champ.value = ''; ouvrir(); })
    .catch(function (e) {
      err.innerHTML = e.status === 400 ? 'Mot de passe incorrect.' : humain(e);
      champ.classList.add('faux');
      champ.select();
      setTimeout(function () { champ.classList.remove('faux'); }, 450);
    })
    .then(function () { bouton.disabled = false; });
});
```

## 6. Bouton Quitter : déconnexion

Avant :

```js
document.getElementById('sortir').addEventListener('click', function () {
  memoire('sdis-ouvert', '');
  location.reload();
});
```

Après :

```js
document.getElementById('sortir').addEventListener('click', function () {
  var a = session && session.access;
  garderSession(null);
  if (!a) { location.reload(); return; }
  fetch(CONFIG.url + '/auth/v1/logout', { method: 'POST',
    headers: { 'apikey': CONFIG.cle, 'Authorization': 'Bearer ' + a } })
    .catch(function () {}).then(function () { location.reload(); });
});
```

## 7. Démarrage (tout à la fin)

Avant :

```js
if (memoire('sdis-ouvert') === '1') ouvrir();
```

Après :

```js
if (session) ouvrir();
```

## 8. Champ de saisie (partie HTML)

Avant :

```html
    <input class="mdp" id="mdp" type="password" inputmode="numeric"
           placeholder="• • • • •" aria-label="Code d'accès" autocomplete="off">
```

Après :

```html
    <input class="mdp" id="mdp" type="password" placeholder="Mot de passe"
           aria-label="Mot de passe" autocomplete="current-password">
```

## 9. Style du champ (partie CSS)

Avant :

```css
.mdp:focus{outline:none;box-shadow:0 0 0 4px var(--acc-halo)}
```

Après :

```css
.mdp:focus{outline:none;box-shadow:0 0 0 4px var(--acc-halo)}
.mdp::placeholder{letter-spacing:.04em;font-size:16px;font-weight:500}
```
