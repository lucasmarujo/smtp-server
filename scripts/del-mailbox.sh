#!/usr/bin/env bash
# Remove uma caixa postal (pede confirmacao).
#   ./del-mailbox.sh usuario@marujo.dev
# Por seguranca NAO apaga os arquivos da mailbox em disco; use --purge para isso.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ADDR="${1:-}"
PURGE="${2:-}"
[ -n "${ADDR}" ] || die "uso: $0 endereco@dominio [--purge]"
require_container

read -r -p "Remover a conta ${ADDR}? (digite 'sim'): " CONF
[ "${CONF}" = "sim" ] || die "cancelado"

if [ "${PURGE}" = "--purge" ]; then
  docker exec -i "${CONTAINER}" setup email del -y "${ADDR}"
  echo "Conta e arquivos removidos."
else
  docker exec -i "${CONTAINER}" setup email del -n "${ADDR}"
  echo "Conta removida. Arquivos preservados em docker-data/dms/mail-data/."
fi

SAFE_NAME="$(echo "${ADDR}" | tr '@/' '_')"
rm -f "${MAIL_DIR}/secrets/${SAFE_NAME}.txt"
