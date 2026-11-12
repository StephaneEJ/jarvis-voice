"""Tests de jarvis_alertes : lecture bornée, déduplication, règles de silence.

Bibliothèque standard seulement (`python3 -m unittest discover -s tests-unitaires`),
car pytest n'est pas installé sur le Mac (voir ROADMAP-DEV.md, Risques ouverts).
"""

import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src" / "claude-hooks"))

import jarvis_alertes as ja  # noqa: E402

CONTRAT_V04 = {  # copie de la forme de contracts/orchestrateur/v0.4/exemples/get_state_summary.json
    "contrat_version": "0.4",
    "sessions": [
        {"id": "claude_code:2", "nom": "Projet A", "outil": "claude_code", "etat": "inconnu",
         "etat_detail": "autorisation_probable", "depuis": "2026-11-11T19:55:00Z",
         "dernier_arret": {"le": "2026-11-11T19:55:00Z", "cause": "autorisation_probable", "heure_exacte": False}},
        {"id": "claude_code:1", "nom": "TEST ORCHESTRATEUR", "outil": "claude_code", "etat": "en_attente",
         "etat_detail": "tour_termine", "depuis": "2026-11-11T19:58:10Z",
         "dernier_arret": {"le": "2026-11-11T19:58:10Z", "cause": "terminee", "heure_exacte": True}},
        {"id": "claude_code:3", "nom": "Projet B", "outil": "claude_code", "etat": "en_cours",
         "etat_detail": "outil_en_cours", "depuis": "2026-11-11T19:59:00Z", "dernier_arret": None},
    ],
}

T0 = datetime(2026, 11, 11, 19, 56, tzinfo=timezone.utc)  # 20:56 à Paris : hors silence


def registre(*fiches):
    """Registre K : `sessions` en dictionnaire, arrêts en liste."""
    return {"mis_a_jour_le": "2026-11-11T19:56:00Z", "sessions": {f["id"]: f for f in fiches}}


def fiche(session_id, nom, etat, detail, arrets, ouverte=True):
    return {"id": session_id, "nom": nom, "etat": etat, "etat_detail": detail, "ouverte": ouverte,
            "depuis": arrets[-1]["le"] if arrets else None, "arrets": arrets}


def arret(le, cause):
    return {"le": le, "cause": cause, "heure_exacte": False}


def config(**options):
    base = dict(silence=None, fuseau="Europe/Paris")
    base.update(options)
    return ja.Config(**base)


def etat_amorce(moment):
    return {"annoncees": {}, "amorce_le": ja.iso(moment - timedelta(hours=1)),
            "derniere_annonce": None, "dernier_point": ja.iso(moment)}


class LectureBornee(unittest.TestCase):
    def test_contrat_v04_seule_l_autorisation_est_un_blocage(self):
        evenements, noms = ja.blocages(CONTRAT_V04)
        self.assertEqual([(e.nom, e.genre) for e in evenements], [("Projet A", "autorisation_probable")])
        self.assertEqual(noms["claude_code:3"], "Projet B")

    def test_registre_k_prend_le_dernier_arret(self):
        donnees = registre(fiche("s1", "Alpha", "en_attente", "erreur",
                                 [arret("2026-11-11T19:00:00Z", "terminee"), arret("2026-11-11T19:50:00Z", "erreur")]))
        evenements, _ = ja.blocages(donnees)
        self.assertEqual(evenements[0].cle, "s1|erreur|2026-11-11T19:50:00Z")

    def test_session_repartie_ou_terminee_n_est_pas_bloquee(self):
        donnees = registre(
            fiche("s1", "Alpha", "en_cours", "outil_en_cours", [arret("2026-11-11T19:50:00Z", "erreur")]),
            fiche("s2", "Beta", "en_attente", "tour_termine", [arret("2026-11-11T19:50:00Z", "terminee")]),
            fiche("s3", "Gamma", "en_attente", "tour_termine", [arret("2026-11-11T19:50:00Z", "autorisation_probable")]),
            fiche("s4", "Delta", "inactive", "surface_fermee", [arret("2026-11-11T19:50:00Z", "erreur")], ouverte=False),
        )
        self.assertEqual(ja.blocages(donnees)[0], [])

    def test_agent_absent_oublie_apres_un_jour(self):
        donnees = registre(fiche("s1", "Alpha", "inactive", "processus_absent",
                                 [arret("2026-11-10T10:00:00Z", "processus_absent")], ouverte=False))
        self.assertEqual(len(ja.blocages(donnees, T0 - timedelta(hours=20))[0]), 1)
        self.assertEqual(ja.blocages(donnees, T0 + timedelta(hours=10))[0], [])

    def test_donnees_invalides_ne_lisent_rien(self):
        for donnees in (None, [], "x", {"sessions": 3}, {"sessions": [1, {"nom": "sans id"}]}):
            self.assertEqual(ja.blocages(donnees)[0], [])
        self.assertEqual(ja.decisions({"decisions": "x"}, {}), [])

    def test_bornes_sessions_et_decisions(self):
        lignes = [{"id": f"s{i}", "nom": "n", "etat": "en_attente", "etat_detail": "erreur",
                   "dernier_arret": arret("2026-11-11T19:50:00Z", "erreur")} for i in range(ja.SESSIONS_MAX + 50)]
        self.assertEqual(len(ja.blocages({"sessions": lignes})[0]), ja.SESSIONS_MAX)
        file_p = [{"id": str(i), "question": "q"} for i in range(ja.DECISIONS_MAX + 5)]
        self.assertEqual(len(ja.decisions(file_p, {})), ja.DECISIONS_MAX)

    def test_fichier_trop_gros_refuse(self):
        with tempfile.TemporaryDirectory() as dossier:
            chemin = Path(dossier) / "registre.json"
            chemin.write_text(" " * (ja.TAILLE_MAX_OCTETS + 1))
            donnees, erreur = ja.lire_json(chemin)
            self.assertIsNone(donnees)
            self.assertIn("trop gros", erreur)
            self.assertEqual(ja.lire_json(Path(dossier) / "absent.json"), (None, None))

    def test_texte_de_session_nettoye_et_secrets_masques(self):
        texte = ja.nettoyer("**Valider** `rm -rf` ?\n token ghp_" + "a" * 30 + " fin", 200)
        self.assertNotIn("ghp_", texte)
        self.assertNotIn("*", texte)
        self.assertNotIn("\n", texte)
        self.assertIn("(secret masqué)", texte)
        self.assertLessEqual(len(ja.nettoyer("x" * 500, 50)), 50)

    def test_file_p_statuts_et_noms(self):
        noms = {"s1": "Alpha"}
        file_p = {"decisions": [
            {"id": "d1", "session_id": "s1", "question": "Fusionner ?", "statut": "en_attente", "cree_le": "2026-11-11T19:55:00Z"},
            {"id": "d2", "session_id": "s1", "question": "Déjà vue", "statut": "repondue"},
            {"id": "d3", "session_nom": "Nuit L", "texte": "Plus tard", "statut": "plus_tard"},
        ]}
        evenements = ja.decisions(file_p, noms)
        self.assertEqual([(e.cle, e.nom) for e in evenements], [("decision|d1", "Alpha"), ("decision|d3", "Nuit L")])


class Deduplication(unittest.TestCase):
    def setUp(self):
        self.donnees = registre(fiche("s1", "Alpha", "inconnu", "autorisation_probable",
                                      [arret("2026-11-11T19:55:00Z", "autorisation_probable")]))
        self.evenements, _ = ja.blocages(self.donnees)

    def test_annoncee_une_seule_fois(self):
        resultat, etat = ja.tick(config(), self.evenements, etat_amorce(T0), T0)
        self.assertEqual(resultat.texte, "Jarvis : Alpha attend probablement une autorisation.")
        for minute in (1, 10, 60, 600):
            resultat, etat = ja.tick(config(), self.evenements, etat, T0 + timedelta(minutes=minute))
            self.assertEqual(resultat.texte, "", minute)

    def test_nouvel_arret_de_la_meme_session_est_neuf(self):
        _, etat = ja.tick(config(), self.evenements, etat_amorce(T0), T0)
        plus_tard = T0 + timedelta(minutes=20)
        donnees = registre(fiche("s1", "Alpha", "inconnu", "autorisation_probable",
                                 [arret("2026-11-11T19:55:00Z", "autorisation_probable"),
                                  arret(ja.iso(plus_tard), "autorisation_probable")]))
        resultat, _ = ja.tick(config(), ja.blocages(donnees)[0], etat, plus_tard)
        self.assertIn("Alpha", resultat.texte)

    def test_blocage_resolu_puis_revu_n_est_pas_repete(self):
        _, etat = ja.tick(config(), self.evenements, etat_amorce(T0), T0)
        _, etat = ja.tick(config(), [], etat, T0 + timedelta(minutes=5))  # résolu : rien
        resultat, _ = ja.tick(config(), self.evenements, etat, T0 + timedelta(minutes=10))
        self.assertEqual(resultat.texte, "")

    def test_premier_passage_sans_rafale(self):
        resultat, etat = ja.tick(config(), self.evenements, None, T0)
        self.assertEqual(resultat.texte, "")
        self.assertIn("amorce_le", etat)
        resultat, _ = ja.tick(config(), self.evenements, etat, T0 + timedelta(minutes=31))
        self.assertTrue(resultat.texte.startswith("Point Jarvis : "))

    def test_memoire_bornee(self):
        etat = etat_amorce(T0)
        vieux = ja.iso(T0 - timedelta(days=8))
        etat["annoncees"] = {f"k{i}": ja.iso(T0 - timedelta(minutes=i)) for i in range(ja.CLES_MEMORISEES_MAX + 20)}
        etat["annoncees"]["perime"] = vieux
        ja.elaguer(etat, set(), T0)
        self.assertNotIn("perime", etat["annoncees"])
        self.assertEqual(len(etat["annoncees"]), ja.CLES_MEMORISEES_MAX)
        self.assertIn("k0", etat["annoncees"])  # les plus récentes restent


class Silence(unittest.TestCase):
    def setUp(self):
        self.donnees = registre(
            fiche("s1", "Alpha", "inconnu", "autorisation_probable", [arret("2026-11-11T19:55:00Z", "autorisation_probable")]),
            fiche("s2", "Beta", "inconnu", "silence_prolonge", [arret("2026-11-11T19:40:00Z", "silence_prolonge")]),
        )
        self.evenements, _ = ja.blocages(self.donnees)

    def test_plage_de_silence(self):
        self.assertTrue(ja.en_silence(23, (22, 7)))
        self.assertTrue(ja.en_silence(3, (22, 7)))
        self.assertFalse(ja.en_silence(7, (22, 7)))
        self.assertTrue(ja.en_silence(13, (12, 14)))
        self.assertFalse(ja.en_silence(3, None))
        self.assertEqual(ja.plage_silence("aucun"), None)
        self.assertEqual(ja.plage_silence("21-6"), (21, 6))
        self.assertEqual(ja.plage_silence("n'importe"), (22, 7))

    def test_heures_de_silence_puis_point_au_reveil(self):
        nuit = datetime(2026, 11, 12, 2, 0, tzinfo=timezone.utc)  # 03:00 à Paris
        donnees = registre(fiche("s1", "Alpha", "inconnu", "autorisation_probable",
                                 [arret(ja.iso(nuit), "autorisation_probable")]))
        evenements = ja.blocages(donnees)[0]
        etat = etat_amorce(nuit)
        resultat, etat = ja.tick(config(silence=(22, 7)), evenements, etat, nuit)
        self.assertEqual((resultat.texte, resultat.motif), ("", "heures de silence"))
        reveil = datetime(2026, 11, 12, 6, 5, tzinfo=timezone.utc)  # 07:05 à Paris
        resultat, _ = ja.tick(config(silence=(22, 7)), evenements, etat, reveil)
        self.assertEqual(resultat.texte, "Point Jarvis : Alpha attend probablement une autorisation.")

    def test_non_urgent_attend_le_point_periodique(self):
        etat = etat_amorce(T0)
        resultat, etat = ja.tick(config(), self.evenements, etat, T0)
        self.assertEqual(resultat.texte, "Jarvis : Alpha attend probablement une autorisation.")
        resultat, etat = ja.tick(config(), self.evenements, etat, T0 + timedelta(minutes=10))
        self.assertEqual((resultat.texte, resultat.motif), ("", "en attente du prochain point"))
        resultat, etat = ja.tick(config(), self.evenements, etat, T0 + timedelta(minutes=30))
        self.assertEqual(resultat.texte, "Point Jarvis : Beta ne donne plus signe de vie.")
        resultat, _ = ja.tick(config(), self.evenements, etat, T0 + timedelta(minutes=90))
        self.assertEqual(resultat.texte, "")

    def test_point_periodique_desactive(self):
        resultat, _ = ja.tick(config(point=None), self.evenements, etat_amorce(T0), T0 + timedelta(hours=5))
        self.assertEqual(resultat.texte, "")  # l'urgent est trop vieux, aucun point périodique

    def test_anti_rafale_regroupe(self):
        etat = etat_amorce(T0)
        _, etat = ja.tick(config(), self.evenements, etat, T0)
        moment = T0 + timedelta(minutes=2)
        nouveaux = registre(
            fiche("s3", "Gamma", "en_attente", "erreur", [arret(ja.iso(moment), "erreur")]),
            fiche("s4", "Delta", "en_attente", "interrompu", [arret(ja.iso(moment), "interrompue")]),
        )
        evenements = self.evenements + ja.blocages(nouveaux)[0]
        resultat, etat = ja.tick(config(), evenements, etat, moment)
        self.assertEqual((resultat.texte, resultat.motif), ("", "anti-rafale"))
        resultat, _ = ja.tick(config(), evenements, etat, T0 + timedelta(minutes=6))
        self.assertEqual(resultat.texte, "Jarvis : Gamma s'est arrêtée sur une erreur ; Delta a été interrompue.")

    def test_vieille_nouvelle_non_urgente(self):
        resultat, _ = ja.tick(config(), self.evenements[:1], etat_amorce(T0), T0 + timedelta(minutes=45))
        self.assertTrue(resultat.texte.startswith("Point Jarvis : "))

    def test_desactive_ne_consomme_rien(self):
        etat = etat_amorce(T0)
        resultat, nouvel_etat = ja.tick(config(active=False), self.evenements, etat, T0)
        self.assertEqual((resultat.texte, nouvel_etat["annoncees"]), ("", {}))

    def test_annonce_limitee_a_trois_details(self):
        lignes = [{"id": f"s{i}", "nom": f"N{i}", "etat": "en_attente", "etat_detail": "erreur",
                   "dernier_arret": arret("2026-11-11T19:55:00Z", "erreur")} for i in range(5)]
        resultat, _ = ja.tick(config(), ja.blocages({"sessions": lignes})[0], etat_amorce(T0), T0)
        self.assertTrue(resultat.texte.endswith("; et 2 autres."))
        self.assertEqual(resultat.texte.count("erreur"), 3)


class PointALaDemande(unittest.TestCase):
    def test_point_complet_meme_deja_annonce(self):
        donnees = registre(fiche("s1", "Alpha", "inconnu", "autorisation_probable",
                                 [arret("2026-11-11T19:55:00Z", "autorisation_probable")]))
        evenements, noms = ja.blocages(donnees)
        evenements += ja.decisions([{"id": "d1", "session_id": "s1", "question": "Fusionner la PR ?",
                                     "cree_le": "2026-11-11T19:50:00Z"}], noms)
        _, etat = ja.tick(config(), evenements, etat_amorce(T0), T0)
        resultat, etat = ja.point(config(silence=(0, 23)), evenements, etat, T0 + timedelta(minutes=1))
        self.assertEqual(resultat.texte, "Point Jarvis : Alpha attend probablement une autorisation ; "
                                         "décision en attente pour Alpha : Fusionner la PR ?")
        resultat, _ = ja.tick(config(), evenements, etat, T0 + timedelta(hours=2))
        self.assertEqual(resultat.texte, "")

    def test_rien_ne_t_attend(self):
        resultat, _ = ja.point(config(), [], None, T0)
        self.assertEqual(resultat.texte, "Point Jarvis : rien ne t'attend.")


class Configuration(unittest.TestCase):
    def test_conf_et_environnement(self):
        valeurs = {"JARVIS_ENABLED": "true", "JARVIS_ALERTES_SILENCE": "aucun", "JARVIS_POINT_MINUTES": "0",
                   "JARVIS_ALERTES_IMMEDIATES": "decision", "JARVIS_COCKPIT_DIR": "~/ailleurs"}
        conf = ja.config_depuis(valeurs, {"JARVIS_ALERTES_ECART_S": "60"})
        self.assertEqual((conf.silence, conf.point, conf.immediates), (None, None, ("decision",)))
        self.assertEqual(conf.ecart, timedelta(seconds=60))
        self.assertEqual(conf.cockpit, Path.home() / "ailleurs")
        self.assertFalse(ja.config_depuis({"JARVIS_ENABLED": "false"}, {}).active)
        self.assertFalse(ja.config_depuis({"JARVIS_ALERTES": "off"}, {}).active)
        self.assertTrue(ja.config_depuis({}, {}).active)


class LigneDeCommande(unittest.TestCase):
    def lancer(self, dossier, *argv):
        sortie, erreurs = io.StringIO(), io.StringIO()
        with redirect_stdout(sortie), redirect_stderr(erreurs):
            code = ja.main([*argv, "--conf", str(dossier / "jarvis.conf"), "--etat", str(dossier / "etat.json")])
        return code, sortie.getvalue().strip()

    def test_parcours_complet_sur_fichiers(self):
        with tempfile.TemporaryDirectory() as brut:
            dossier = Path(brut)
            (dossier / "orchestrateur").mkdir()
            (dossier / "jarvis.conf").write_text(f"JARVIS_COCKPIT_DIR={dossier}\nJARVIS_ALERTES_SILENCE=aucun\n")
            (dossier / "orchestrateur/registre.json").write_text(json.dumps(registre(
                fiche("s1", "Alpha", "inconnu", "autorisation_probable", [arret("2026-11-11T19:55:00Z", "autorisation_probable")]))))
            amorce = dict(etat_amorce(T0))
            (dossier / "etat.json").write_text(json.dumps(amorce))
            self.assertEqual(self.lancer(dossier, "tick", "--simuler", "--maintenant", ja.iso(T0))[1],
                             "Jarvis : Alpha attend probablement une autorisation.")
            self.assertEqual(json.loads((dossier / "etat.json").read_text()), amorce)  # simulé : rien retenu
            self.assertIn("Alpha", self.lancer(dossier, "tick", "--maintenant", ja.iso(T0))[1])
            self.assertEqual(self.lancer(dossier, "tick", "--maintenant", ja.iso(T0 + timedelta(minutes=1)))[1], "")
            code, sortie = self.lancer(dossier, "etat", "--maintenant", ja.iso(T0))
            self.assertEqual((code, json.loads(sortie)["non_annonces"]), (0, 0))

    def test_registre_absent_silence(self):
        with tempfile.TemporaryDirectory() as brut:
            dossier = Path(brut)
            (dossier / "jarvis.conf").write_text(f"JARVIS_COCKPIT_DIR={dossier}\n")
            self.assertEqual(self.lancer(dossier, "tick", "--maintenant", ja.iso(T0)), (0, ""))


if __name__ == "__main__":
    unittest.main()
