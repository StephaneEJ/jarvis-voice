#!/usr/bin/env python3
"""jarvis_alertes — annonces de blocage et de décisions en attente (résultat Q).

Lit, en lecture seule et de façon bornée, deux fichiers tenus par le Cockpit Jarvis :

- le registre du superviseur K (`<cockpit>/orchestrateur/registre.json`), ou une
  sortie `get_state_summary` du contrat orchestrateur v0.4 (même champs utiles) ;
- la file des décisions P (`<cockpit>/orchestrateur/decisions.json`, format
  provisoire tant que P n'est pas livré : voir `docs/ALERTES-COCKPIT.md`).

Il décide quoi dire, et quand, selon des règles propres à jarvis-voice :
une alerte n'est annoncée qu'une seule fois, l'urgent part tout de suite (hors
heures de silence et hors rafale), le reste est regroupé en points périodiques
ou à la demande. Il n'émet que du texte sur la sortie standard : la voix est
jouée par `jarvis alertes` (bash ou PowerShell) avec la synthèse existante.

Aucune écriture hors du fichier d'état de jarvis-voice. Aucune dépendance hors
bibliothèque standard (Python 3.9 et plus).

Usage :
    jarvis_alertes.py tick  [--simuler] [--maintenant ISO]   annonce immédiate ou point périodique
    jarvis_alertes.py point [--simuler] [--maintenant ISO]   point complet à la demande
    jarvis_alertes.py etat  [--maintenant ISO]               diagnostic JSON, ne change rien
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# --- Bornes de lecture -------------------------------------------------------
TAILLE_MAX_OCTETS = 2_000_000
SESSIONS_MAX = 200
DECISIONS_MAX = 100
NOM_MAX = 60
QUESTION_MAX = 160
DETAILS_PAR_ANNONCE = 3
CLES_MEMORISEES_MAX = 500
RETENTION_CLES = timedelta(days=7)
AGENT_ABSENT_OUBLIE = timedelta(hours=24)  # session sans agent : oubliée après un jour

CAUSES_BLOCAGE = ("autorisation_probable", "erreur", "interrompue", "silence_prolonge", "processus_absent")
STATUTS_DECISION_OUVERTS = ("en_attente", "plus_tard")

LIBELLES = {
    "autorisation_probable": "attend probablement une autorisation",
    "erreur": "s'est arrêtée sur une erreur",
    "interrompue": "a été interrompue",
    "silence_prolonge": "ne donne plus signe de vie",
    "processus_absent": "n'a plus d'agent actif",
}

COCKPIT_PAR_DEFAUT = Path.home() / "OBSIDIAN/2ND_CERVEAU/_System/Jarvis/Cockpit"
CONF_PAR_DEFAUT = Path.home() / ".claude/jarvis.conf"
ETAT_PAR_DEFAUT = Path.home() / ".claude/jarvis-alertes-etat.json"

SECRETS = re.compile(
    r"(sk-[A-Za-z0-9_\-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}"
    r"|xox[abprs]-[A-Za-z0-9\-]{10,}|AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{5,}"
    r"|[A-Za-z0-9_\-]{40,})"
)


# --- Configuration -------------------------------------------------------------
@dataclass
class Config:
    active: bool = True
    cockpit: Path = COCKPIT_PAR_DEFAUT
    silence: Optional[Tuple[int, int]] = (22, 7)
    ecart: timedelta = timedelta(seconds=300)
    point: Optional[timedelta] = timedelta(minutes=30)
    age_max: timedelta = timedelta(minutes=30)
    immediates: Tuple[str, ...] = ("autorisation_probable", "erreur", "interrompue", "decision")
    fuseau: Optional[str] = None


def lire_conf(chemin: Path) -> Dict[str, str]:
    valeurs: Dict[str, str] = {}
    try:
        if chemin.stat().st_size > TAILLE_MAX_OCTETS:
            return valeurs
        texte = chemin.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return valeurs
    for ligne in texte.splitlines():
        ligne = ligne.strip()
        if not ligne or ligne.startswith("#") or "=" not in ligne:
            continue
        cle, valeur = ligne.split("=", 1)
        valeurs[cle.strip()] = valeur.strip()
    return valeurs


def _entier(valeur: Optional[str], defaut: int) -> int:
    try:
        return int(str(valeur).strip())
    except (TypeError, ValueError):
        return defaut


def plage_silence(valeur: Optional[str]) -> Optional[Tuple[int, int]]:
    """« 22-07 » → (22, 7) ; « aucun », vide invalide → pas de silence."""
    if valeur is None:
        return (22, 7)
    valeur = valeur.strip().lower()
    if valeur in ("", "aucun", "off", "non"):
        return None
    morceaux = valeur.split("-")
    if len(morceaux) != 2:
        return (22, 7)
    debut, fin = _entier(morceaux[0], -1), _entier(morceaux[1], -1)
    if not (0 <= debut <= 23 and 0 <= fin <= 23) or debut == fin:
        return (22, 7)
    return (debut, fin)


def config_depuis(valeurs: Dict[str, str], environ: Optional[Dict[str, str]] = None) -> Config:
    environ = dict(os.environ if environ is None else environ)
    def lire(cle: str) -> Optional[str]:
        return environ.get(cle, valeurs.get(cle))
    actif = (lire("JARVIS_ENABLED") or "true").lower() != "false" and (lire("JARVIS_ALERTES") or "on").lower() != "off"
    point_min = _entier(lire("JARVIS_POINT_MINUTES"), 30)
    immediates = tuple(c.strip() for c in (lire("JARVIS_ALERTES_IMMEDIATES") or "").split(",") if c.strip())
    return Config(
        active=actif,
        cockpit=Path(os.path.expanduser(lire("JARVIS_COCKPIT_DIR") or str(COCKPIT_PAR_DEFAUT))),
        silence=plage_silence(lire("JARVIS_ALERTES_SILENCE")),
        ecart=timedelta(seconds=max(0, _entier(lire("JARVIS_ALERTES_ECART_S"), 300))),
        point=timedelta(minutes=point_min) if point_min > 0 else None,
        age_max=timedelta(minutes=max(1, _entier(lire("JARVIS_ALERTES_AGE_MAX_MIN"), 30))),
        immediates=immediates or Config.immediates,
        fuseau=lire("JARVIS_ALERTES_FUSEAU") or None,
    )


# --- Temps -------------------------------------------------------------------
def lire_horodatage(valeur: object) -> Optional[datetime]:
    if not isinstance(valeur, str) or not valeur or len(valeur) > 40:
        return None
    texte = valeur.strip()
    if texte.endswith("Z"):
        texte = texte[:-1] + "+00:00"
    try:
        moment = datetime.fromisoformat(texte)
    except ValueError:
        return None
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


def iso(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def heure_locale(moment: datetime, fuseau: Optional[str]) -> int:
    if fuseau:
        try:
            from zoneinfo import ZoneInfo
            return moment.astimezone(ZoneInfo(fuseau)).hour
        except Exception:  # fuseau inconnu ou base absente (Windows sans tzdata)
            pass
    return moment.astimezone().hour


def en_silence(heure: int, plage: Optional[Tuple[int, int]]) -> bool:
    if plage is None:
        return False
    debut, fin = plage
    return debut <= heure < fin if debut < fin else (heure >= debut or heure < fin)


# --- Lecture bornée ----------------------------------------------------------
def lire_json(chemin: Path) -> Tuple[Optional[object], Optional[str]]:
    try:
        taille = chemin.stat().st_size
    except FileNotFoundError:
        return None, None  # absent : rien à dire, pas une erreur
    except OSError as erreur:
        return None, f"{chemin.name} illisible ({erreur.__class__.__name__})"
    if taille > TAILLE_MAX_OCTETS:
        return None, f"{chemin.name} trop gros ({taille} octets)"
    try:
        return json.loads(chemin.read_text(encoding="utf-8")), None
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as erreur:
        return None, f"{chemin.name} invalide ({erreur.__class__.__name__})"


def nettoyer(texte: object, limite: int) -> str:
    """Texte venu d'une session : non fiable, lu à voix haute."""
    if not isinstance(texte, str):
        return ""
    texte = SECRETS.sub("(secret masqué)", texte)
    texte = re.sub(r"[\x00-\x1f\x7f]", " ", texte)
    texte = re.sub(r"[`*_#<>\[\]{}|~]", " ", texte)
    texte = re.sub(r"\s+", " ", texte).strip()
    if len(texte) > limite:
        texte = texte[: limite - 1].rstrip() + "…"
    return texte


@dataclass
class Evenement:
    cle: str
    genre: str  # cause de blocage, ou « decision »
    session_id: str
    nom: str
    le: Optional[datetime]
    question: str = ""


def _lignes_sessions(donnees: object) -> List[Tuple[str, dict]]:
    """Registre K (`sessions` en dictionnaire) ou `get_state_summary` (`sessions` en liste)."""
    if not isinstance(donnees, dict):
        return []
    sessions = donnees.get("sessions")
    lignes: List[Tuple[str, dict]] = []
    if isinstance(sessions, dict):
        for session_id, fiche in list(sessions.items())[:SESSIONS_MAX]:
            if isinstance(fiche, dict):
                arrets = fiche.get("arrets")
                fiche = dict(fiche)
                fiche["dernier_arret"] = arrets[-1] if isinstance(arrets, list) and arrets else None
                lignes.append((str(session_id), fiche))
    elif isinstance(sessions, list):
        for ligne in sessions[:SESSIONS_MAX]:
            if isinstance(ligne, dict) and ligne.get("id"):
                lignes.append((str(ligne["id"]), ligne))
    return lignes


def _surfaces_occupees(lignes: List[Tuple[str, dict]]) -> Dict[str, set]:
    """Surface cmux → sessions ouvertes qui l'occupent (registre K seulement : le contrat v0.4 n'a pas la surface)."""
    occupees: Dict[str, set] = {}
    for session_id, fiche in lignes:
        surface = fiche.get("surface_id")
        if isinstance(surface, str) and surface and fiche.get("ouverte") is not False and fiche.get("etat") != "inactive":
            occupees.setdefault(surface, set()).add(session_id)
    return occupees


def blocages(donnees: object, maintenant: Optional[datetime] = None) -> Tuple[List[Evenement], Dict[str, str]]:
    evenements: List[Evenement] = []
    noms: Dict[str, str] = {}
    lignes = _lignes_sessions(donnees)
    occupees = _surfaces_occupees(lignes)
    for session_id, fiche in lignes:
        nom = nettoyer(fiche.get("nom"), NOM_MAX) or "sans nom"
        noms[session_id] = nom
        etat, detail = fiche.get("etat"), fiche.get("etat_detail")
        if etat == "en_cours":
            continue  # elle travaille : rien ne l'arrête
        arret = fiche.get("dernier_arret") if isinstance(fiche.get("dernier_arret"), dict) else None
        cause = arret.get("cause") if arret else None
        if cause not in CAUSES_BLOCAGE:
            continue  # tour terminé, compactée, fermée : la voix de fin de réponse s'en charge
        if fiche.get("ouverte") is False and cause != "processus_absent":
            continue
        if cause in ("autorisation_probable", "silence_prolonge") and detail != cause:
            continue  # l'état a changé depuis : l'arrêt n'est plus actuel
        le_brut = arret.get("le") or fiche.get("depuis")
        le = lire_horodatage(le_brut)
        if cause == "processus_absent" and maintenant and le and maintenant - le > AGENT_ABSENT_OUBLIE:
            continue
        if cause == "processus_absent" and occupees.get(fiche.get("surface_id"), set()) - {session_id}:
            continue  # la surface porte une autre conversation (/clear, relance) : l'agent n'est pas absent
        evenements.append(Evenement(
            cle=f"{session_id}|{cause}|{le_brut}", genre=cause, session_id=session_id,
            nom=nom, le=le,
        ))
    return evenements, noms


def decisions(donnees: object, noms: Dict[str, str]) -> List[Evenement]:
    """File P, format provisoire : liste, ou `{"decisions": [...]}`."""
    if isinstance(donnees, dict):
        donnees = donnees.get("decisions")
    if not isinstance(donnees, list):
        return []
    evenements = []
    for decision in donnees[:DECISIONS_MAX]:
        if not isinstance(decision, dict) or not decision.get("id"):
            continue
        statut = decision.get("statut", "en_attente")
        if statut not in STATUTS_DECISION_OUVERTS:
            continue
        session_id = str(decision.get("session_id") or "")
        nom = nettoyer(decision.get("session_nom"), NOM_MAX) or noms.get(session_id) or "une session"
        evenements.append(Evenement(
            cle=f"decision|{nettoyer(str(decision['id']), 80)}", genre="decision", session_id=session_id,
            nom=nom, le=lire_horodatage(decision.get("cree_le") or decision.get("le")),
            question=nettoyer(decision.get("question") or decision.get("texte"), QUESTION_MAX),
        ))
    return evenements


def collecter(config: Config, maintenant: Optional[datetime] = None) -> Tuple[List[Evenement], List[str]]:
    dossier = config.cockpit / "orchestrateur"
    erreurs: List[str] = []
    registre, erreur = lire_json(dossier / "registre.json")
    if erreur:
        erreurs.append(erreur)
    evenements, noms = blocages(registre, maintenant)
    file_p, erreur = lire_json(dossier / "decisions.json")
    if erreur:
        erreurs.append(erreur)
    evenements.extend(decisions(file_p, noms))
    return evenements, erreurs


# --- État de jarvis-voice (déduplication) ---------------------------------------
def lire_etat(chemin: Path) -> Optional[dict]:
    donnees, _ = lire_json(chemin)
    if not isinstance(donnees, dict) or not isinstance(donnees.get("annoncees"), dict):
        return None
    return donnees


def ecrire_etat(chemin: Path, etat: dict) -> None:
    chemin.parent.mkdir(parents=True, exist_ok=True)
    descripteur, temporaire = tempfile.mkstemp(prefix=".jarvis-alertes-", dir=str(chemin.parent))
    try:
        with os.fdopen(descripteur, "w", encoding="utf-8") as fichier:
            json.dump(etat, fichier, ensure_ascii=False, indent=1, sort_keys=True)
        os.replace(temporaire, chemin)
    except BaseException:
        try:
            os.unlink(temporaire)
        except OSError:
            pass
        raise


def elaguer(etat: dict, vivantes: set, maintenant: datetime) -> None:
    annoncees = etat["annoncees"]
    for cle, le in list(annoncees.items()):
        moment = lire_horodatage(le)
        if cle not in vivantes and (moment is None or maintenant - moment > RETENTION_CLES):
            del annoncees[cle]
    if len(annoncees) > CLES_MEMORISEES_MAX:
        for cle, _ in sorted(annoncees.items(), key=lambda item: item[1])[: len(annoncees) - CLES_MEMORISEES_MAX]:
            del annoncees[cle]


# --- Phrases -----------------------------------------------------------------
def phrase(evenement: Evenement) -> str:
    if evenement.genre == "decision":
        if evenement.question:
            return f"décision en attente pour {evenement.nom} : {evenement.question}"
        return f"décision en attente pour {evenement.nom}"
    return f"{evenement.nom} {LIBELLES.get(evenement.genre, 'est bloquée')}"


def annonce(evenements: List[Evenement], prefixe: str) -> str:
    details = [phrase(e) for e in evenements[:DETAILS_PAR_ANNONCE]]
    reste = len(evenements) - len(details)
    texte = " ; ".join(details)
    if reste > 0:
        texte += f" ; et {reste} autre{'s' if reste > 1 else ''}"
    texte = texte[0].upper() + texte[1:] if texte else texte
    fin = "" if texte.endswith(("?", "!", ".", "…")) else "."
    return f"{prefixe}{texte}{fin}"


def _ordre(evenement: Evenement) -> Tuple[int, float]:
    rang = {"autorisation_probable": 0, "decision": 1, "erreur": 2, "interrompue": 3,
            "processus_absent": 4, "silence_prolonge": 5}.get(evenement.genre, 9)
    return rang, (evenement.le.timestamp() if evenement.le else 0.0)


# --- Décision : quoi dire maintenant ------------------------------------------------
@dataclass
class Resultat:
    texte: str = ""
    annoncees: List[str] = field(default_factory=list)
    motif: str = ""


def tick(config: Config, evenements: List[Evenement], etat: Optional[dict], maintenant: datetime) -> Tuple[Resultat, dict]:
    """Une passe : au plus une phrase. L'état rendu est celui à écrire."""
    if etat is None:  # premier passage : ce qui existe déjà ira au prochain point, pas en rafale
        etat = {"annoncees": {}, "amorce_le": iso(maintenant), "derniere_annonce": None, "dernier_point": iso(maintenant)}
    etat = json.loads(json.dumps(etat))
    elaguer(etat, {e.cle for e in evenements}, maintenant)
    if not config.active:
        return Resultat(motif="désactivé"), etat
    nouveaux = sorted((e for e in evenements if e.cle not in etat["annoncees"]), key=_ordre)
    if not nouveaux:
        return Resultat(motif="rien de nouveau"), etat
    if en_silence(heure_locale(maintenant, config.fuseau), config.silence):
        return Resultat(motif="heures de silence"), etat
    amorce = lire_horodatage(etat.get("amorce_le"))
    derniere = lire_horodatage(etat.get("derniere_annonce"))

    def immediat(e: Evenement) -> bool:
        if e.genre not in config.immediates or e.le is None:
            return False
        if amorce is not None and e.le < amorce:
            return False
        return maintenant - e.le <= config.age_max

    urgents = [e for e in nouveaux if immediat(e)]
    if urgents and (derniere is None or maintenant - derniere >= config.ecart):
        return _dire(etat, urgents, maintenant, "Jarvis : ", "annonce"), etat
    dernier_point = lire_horodatage(etat.get("dernier_point"))
    if config.point is not None and (dernier_point is None or maintenant - dernier_point >= config.point):
        resultat = _dire(etat, nouveaux, maintenant, "Point Jarvis : ", "point périodique")
        etat["dernier_point"] = iso(maintenant)
        return resultat, etat
    return Resultat(motif="en attente du prochain point" if not urgents else "anti-rafale"), etat


def point(config: Config, evenements: List[Evenement], etat: Optional[dict], maintenant: datetime) -> Tuple[Resultat, dict]:
    """Point demandé par Stéphane : tout ce qui est ouvert, même déjà annoncé, sans règle de silence."""
    if etat is None:
        etat = {"annoncees": {}, "amorce_le": iso(maintenant), "derniere_annonce": None, "dernier_point": None}
    etat = json.loads(json.dumps(etat))
    elaguer(etat, {e.cle for e in evenements}, maintenant)
    etat["dernier_point"] = iso(maintenant)
    if not evenements:
        return Resultat(texte="Point Jarvis : rien ne t'attend.", motif="point à la demande"), etat
    ouverts = sorted(evenements, key=_ordre)
    return _dire(etat, ouverts, maintenant, "Point Jarvis : ", "point à la demande"), etat


def _dire(etat: dict, evenements: List[Evenement], maintenant: datetime, prefixe: str, motif: str) -> Resultat:
    for e in evenements:
        etat["annoncees"][e.cle] = iso(maintenant)
    if motif == "annonce":
        etat["derniere_annonce"] = iso(maintenant)
    return Resultat(texte=annonce(evenements, prefixe), annoncees=[e.cle for e in evenements], motif=motif)


# --- Ligne de commande -------------------------------------------------------------
def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Annonces Jarvis de blocage et de décisions en attente")
    parser.add_argument("commande", choices=("tick", "point", "etat"))
    parser.add_argument("--simuler", action="store_true", help="affiche sans retenir l'annonce")
    parser.add_argument("--maintenant", help="horodatage ISO (essais)")
    parser.add_argument("--conf", type=Path, default=CONF_PAR_DEFAUT)
    parser.add_argument("--etat", type=Path, default=Path(os.environ.get("JARVIS_ALERTES_ETAT", str(ETAT_PAR_DEFAUT))))
    args = parser.parse_args(argv)

    maintenant = lire_horodatage(args.maintenant) if args.maintenant else datetime.now(timezone.utc)
    if maintenant is None:
        print("horodatage invalide", file=sys.stderr)
        return 2
    config = config_depuis(lire_conf(args.conf))
    evenements, erreurs = collecter(config, maintenant)
    etat = lire_etat(args.etat)
    for erreur in erreurs:
        print(f"jarvis-alertes : {erreur}", file=sys.stderr)

    if args.commande == "etat":
        nouveaux = [e for e in evenements if not etat or e.cle not in etat["annoncees"]]
        print(json.dumps({
            "active": config.active, "cockpit": str(config.cockpit), "erreurs": erreurs,
            "ouverts": [{"genre": e.genre, "nom": e.nom, "le": iso(e.le) if e.le else None} for e in evenements],
            "non_annonces": len(nouveaux),
            "silence_maintenant": en_silence(heure_locale(maintenant, config.fuseau), config.silence),
        }, ensure_ascii=False, indent=1))
        return 0

    action = tick if args.commande == "tick" else point
    resultat, nouvel_etat = action(config, evenements, etat, maintenant)
    if not args.simuler and (resultat.texte or etat is None):
        ecrire_etat(args.etat, nouvel_etat)
    if resultat.texte:
        print(resultat.texte)
    else:
        print(f"jarvis-alertes : silence ({resultat.motif})", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
