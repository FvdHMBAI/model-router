#!/bin/bash
set -e
G=$'\033[0;32m' R=$'\033[0;31m' Y=$'\033[0;33m' B=$'\033[1m' D=$'\033[2m' Z=$'\033[0m' C=$'\033[0;36m'

type_cmd() {
  printf "${D}\$ ${Z}"
  for ((i=0; i<${#1}; i++)); do printf "%s" "${1:$i:1}"; sleep 0.03; done
  echo ""
}

clear
echo ""
echo "  ${B}Model Router${Z} ${D}v1.0${Z}"
echo "  ${D}One config file, every model, zero dependencies${Z}"
echo ""
sleep 1

type_cmd "eval \$(model-router standard)"
sleep 0.3
echo "  ${C}MODEL_ID${Z}=${B}claude-sonnet-5${Z}  ${D}# standard tier${Z}"
echo ""
sleep 0.8

type_cmd "eval \$(model-router cheap)"
sleep 0.3
echo "  ${C}MODEL_ID${Z}=${B}claude-haiku-4-5${Z}  ${D}# cheap tier${Z}"
echo ""
sleep 0.8

type_cmd "eval \$(model-router premium)"
sleep 0.3
echo "  ${C}MODEL_ID${Z}=${B}claude-opus-4-6${Z}  ${D}# premium tier${Z}"
echo ""
sleep 1

type_cmd "cat ~/.config/model-router/config.json | jq '.tiers'"
sleep 0.5

echo "  ${D}{${Z}"
echo "    ${C}\"cheap\"${Z}:    ${D}\"claude-haiku-4-5\",${Z}"
echo "    ${C}\"standard\"${Z}: ${D}\"claude-sonnet-5\",${Z}"
echo "    ${C}\"premium\"${Z}:  ${D}\"claude-opus-4-6\",${Z}"
echo "    ${C}\"vision\"${Z}:   ${D}\"claude-sonnet-5\"${Z}"
echo "  ${D}}${Z}"
echo ""
sleep 1

echo "  ${B}New model?${Z} Update ${D}one file${Z}. ${B}30 scripts${Z} stay untouched."
echo ""
sleep 3
