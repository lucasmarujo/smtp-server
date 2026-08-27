#!/usr/bin/env bash
# Funcoes/variaveis compartilhadas pelos scripts de manutencao.
set -euo pipefail

MAIL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "${MAIL_DIR}/docker-compose.yml")
SERVICE=mailserver   # nome do servico no docker-compose.yml
CONTAINER=mail       # container_name / hostname

cd "${MAIL_DIR}"

die() {
  echo "ERRO: $*" >&2
  exit 1
}

require_container() {
  docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null | grep -q true \
    || die "container '${CONTAINER}' nao esta rodando. Suba com: ${COMPOSE[*]} up -d"
}
