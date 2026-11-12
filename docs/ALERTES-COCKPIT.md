# Alertes du Cockpit — interface bornée et règles de silence (résultat Q)

`jarvis alertes` annonce à la voix, une seule fois, qu'une session pilotée est bloquée ou qu'une décision attend Stéphane. Le reste est regroupé en points périodiques ou à la demande. Le code est `src/claude-hooks/jarvis_alertes.py` (bibliothèque standard, Python 3.9 et plus) ; la voix passe par `_speak.sh` / `_speak.ps1`.

## Interface avec le Cockpit (lecture seule)

`jarvis-voice` lit deux fichiers dans `JARVIS_COCKPIT_DIR` (par défaut `~/OBSIDIAN/2ND_CERVEAU/_System/Jarvis/Cockpit`). Il n'importe aucun code du Cockpit et n'écrit jamais dans ce dossier.

| Fichier | Tenu par | Champs lus |
|---|---|---|
| `orchestrateur/registre.json` | superviseur K (`jarvis_cockpit/orchestrateur/superviseur.py`) | `sessions.<id>.{nom, etat, etat_detail, ouverte, depuis, arrets[-1].{le, cause}}` |
| ou une sortie `get_state_summary` (contrat orchestrateur v0.4) | serveur MCP | `sessions[].{id, nom, etat, etat_detail, depuis, dernier_arret.{le, cause}}` |
| `orchestrateur/decisions.json` | file P (**provisoire**, P pas encore livré) | liste ou `{"decisions": [...]}` ; chaque entrée : `id`, `statut` (`en_attente`, `plus_tard`, sinon fermée), `session_id` ou `session_nom`, `question` ou `texte`, `cree_le` |

Le format de la file P est une hypothèse de `jarvis-voice` : quand P sera livré dans le Cockpit, son contrat prime et ce lecteur s'aligne (champ inconnu ignoré, fichier absent = aucune décision).

**Bornes :** fichier de plus de 2 Mo refusé ; 200 sessions et 100 décisions au plus ; nom tronqué à 60 caractères, question à 160 ; caractères de contrôle et balises retirés ; motifs de secrets (`sk-…`, `ghp_…`, `github_pat_…`, `xox…`, `AKIA…`, JWT, chaînes de 40 caractères et plus) remplacés par « secret masqué » avant toute lecture à voix haute. Un fichier absent ou invalide donne le silence, jamais une annonce inventée.

## Ce qui est un blocage

Une session qui ne travaille pas (`etat` différent de `en_cours`) et dont le dernier arrêt est :

| Cause K | Phrase | Par défaut |
|---|---|---|
| `autorisation_probable` (et `etat_detail` identique) | « attend probablement une autorisation » | immédiat |
| `erreur` | « s'est arrêtée sur une erreur » | immédiat |
| `interrompue` | « a été interrompue » | immédiat |
| `silence_prolonge` (et `etat_detail` identique) | « ne donne plus signe de vie » | point |
| `processus_absent` (oublié après 24 h ; ignoré si la même surface cmux porte une autre session ouverte, cas d'un `/clear` ou d'une relance) | « n'a plus d'agent actif » | point |
| décision P ouverte | « décision en attente pour <session> : <question> » | immédiat |

`terminee`, `compactee` et `fermee` ne sont pas des blocages : la fin de réponse est déjà dite par `voice-stop`.

Observé sur une session de test réelle (C3, 12/11/2026) : une autorisation accordée **ou refusée par Échap** donne un arrêt `terminee` chez K, donc aucune annonce de suite. Une commande longue sans écriture de transcript (plus de 2 min) est vue par K comme `autorisation_probable` : si elle reprend avant l'annonce (anti-rafale), rien n'est dit ; sinon l'annonce part, à tort. Ce faux positif vient de l'heuristique de K, pas de `jarvis-voice`.

## Déduplication

Clé d'une alerte : `<session>|<cause>|<horodatage de l'arrêt>`, ou `decision|<id>`. Une clé annoncée n'est plus jamais redite, même si le blocage disparaît puis réapparaît identique ; un nouvel arrêt de la même session (autre horodatage) est une nouvelle alerte. Mémoire : `~/.claude/jarvis-alertes-etat.json` (écriture atomique), clés oubliées 7 jours après la disparition de l'alerte, 500 au plus.

## Règles de silence (propres à jarvis-voice)

`jarvis alertes tick` dit au plus une phrase par passage :

1. `JARVIS_ENABLED=false` ou `JARVIS_ALERTES=off` : rien, et rien n'est consommé.
2. Heures de silence (`JARVIS_ALERTES_SILENCE`, défaut `22-07`, heure locale ou `JARVIS_ALERTES_FUSEAU`) : rien ; tout attend le premier point après la plage.
3. Annonce immédiate des alertes urgentes (`JARVIS_ALERTES_IMMEDIATES`) récentes (moins de `JARVIS_ALERTES_AGE_MAX_MIN`, défaut 30 min), regroupées en une phrase (3 détails, puis « et N autres »), au plus une fois toutes les `JARVIS_ALERTES_ECART_S` secondes (défaut 300) : au-delà, elles attendent la fin de l'écart.
4. Sinon, point périodique toutes les `JARVIS_POINT_MINUTES` (défaut 30, `0` pour désactiver) avec ce qui n'a pas encore été dit ; aucun point s'il n'y a rien de neuf.
5. Premier passage (pas de mémoire) : rien n'est dit en rafale, ce qui existe déjà part au premier point.

`jarvis alertes` (ou `jarvis alertes point`) est le point à la demande : tout ce qui est ouvert, même déjà annoncé, sans règle de silence ; « rien ne t'attend » s'il n'y a rien.

## Commandes

```bash
jarvis alertes                 # point à la demande, à voix haute
jarvis alertes tick            # passage des règles (à appeler par une boucle ou un cron)
jarvis alertes etat            # diagnostic JSON, sans voix et sans rien retenir
jarvis alertes tick --texte    # écrit la phrase sans la dire (la nuit, essais)
jarvis alertes tick --simuler  # écrit la phrase sans la retenir
```

Aucun cron ni boucle n'est installé par ce dépôt : le rythme d'appel de `tick` reste à valider avec Stéphane. L'annonce est retenue avant d'être jouée (au plus une fois) : si la synthèse échoue, elle n'est pas répétée.
