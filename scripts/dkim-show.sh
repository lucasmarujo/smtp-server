#!/usr/bin/env bash
# Mostra (ou gera) a chave DKIM e o registro TXT a ser publicado no DNS.
#   ./dkim-show.sh                       -> mostra a chave atual
#   ./dkim-show.sh --generate <dominio>  -> gera nova chave (selector 'mail')
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ACTION="${1:-show}"
DKIM_DIR="${MAIL_DIR}/docker-data/dms/config/rspamd/dkim"

if [ "${ACTION}" = "--generate" ]; then
  DOMAIN="${2:-}"
  [ -n "${DOMAIN}" ] || die "uso: $0 --generate dominio"
  require_container
  docker exec -i "${CONTAINER}" setup config dkim domain "${DOMAIN}" selector mail
  docker restart "${CONTAINER}" >/dev/null
fi

echo "== Registros TXT DKIM a publicar =="
for f in "${DKIM_DIR}"/*public.dns.txt; do
  [ -e "${f}" ] || { echo "(nenhuma chave encontrada em ${DKIM_DIR})"; exit 1; }
  base="$(basename "${f}")"
  dom="$(echo "${base}" | sed -E 's/^rsa-[0-9]+-mail-(.*)\.public\.dns\.txt$/\1/')"
  echo
  echo "Nome:  mail._domainkey.${dom}"
  echo "Tipo:  TXT"
  echo "Valor: $(cat "${f}")"
done
