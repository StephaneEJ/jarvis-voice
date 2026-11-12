#!/usr/bin/env bash
# check.sh — contrôle du dépôt avant commit.
# Rejoue les contrôles du critère de nuit : bash -n sur chaque .sh, node --check
# sur chaque .js, pytest si un dossier tests/ existe, unittest sur tests-unitaires/,
# et git diff --check.
set -u
cd "$(dirname "$0")/.." || exit 1

echecs=0
controler() {
    if "$@" >/dev/null 2>&1; then
        echo "ok      $*"
    else
        echo "ÉCHEC   $*"
        echecs=$((echecs + 1))
    fi
}

while IFS= read -r f; do controler bash -n "$f"; done < <(git ls-files '*.sh')
if command -v node >/dev/null 2>&1; then
    while IFS= read -r f; do controler node --check "$f"; done < <(git ls-files '*.js')
else
    echo "ÉCHEC   node absent : node --check impossible"
    echecs=$((echecs + 1))
fi
[[ -d tests ]] && controler python3 -m pytest -q
# Tests unitaires sans dépendance (pytest absent du Mac) : bibliothèque standard seulement.
[[ -d tests-unitaires ]] && controler python3 -m unittest discover -s tests-unitaires -q
controler git diff --check
controler git diff --cached --check

if [[ $echecs -gt 0 ]]; then
    echo "$echecs contrôle(s) en échec"
    exit 1
fi
echo "tous les contrôles passent"
