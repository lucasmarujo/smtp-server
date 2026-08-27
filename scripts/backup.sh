#!/usr/bin/env bash
# Backup completo do servidor de e-mail.
# Gera um tarball em backups/ com: configuracao, contas, aliases, mailboxes,
# chaves DKIM, certificado TLS de fallback, scripts e .env.
# NAO remove backups antigos automaticamente.
#
#   ./backup.sh                 cria um backup
#   ./backup.sh --prune <dias>  remove backups mais antigos que <dias> (manual)
#
# O tar roda dentro de um container efemero como root (a imagem do DMS) porque
# parte dos dados em docker-data/ pertence ao root. NAO inclui
# docker-data/dms/mail-state/ (estado de runtime regenerado pelo container).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BACKUP_DIR="${MAIL_DIR}/backups"
mkdir -p "${BACKUP_DIR}"

if [ "${1:-}" = "--prune" ]; then
  DAYS="${2:-}"
  [ -n "${DAYS}" ] || die "uso: $0 --prune <dias>"
  echo "Removendo backups com mais de ${DAYS} dias..."
  find "${BACKUP_DIR}" -maxdepth 1 -name 'mail-backup-*.tar.gz*' -mtime "+${DAYS}" -print -delete
  exit 0
fi

HELPER_IMAGE="$(grep -E '^DMS_IMAGE=' "${MAIL_DIR}/.env" | cut -d= -f2)"
TS="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="${BACKUP_DIR}/mail-backup-${TS}.tar.gz"

docker run --rm --entrypoint tar \
  -v "${MAIL_DIR}:/data:ro" \
  "${HELPER_IMAGE}" \
  czf - -C /data \
  --ignore-failed-read \
  docker-compose.yml \
  .env \
  .env.example \
  .gitignore \
  config \
  scripts \
  docker-data/dms/config \
  docker-data/dms/mail-data \
  docker-data/roundcube/db \
  secrets > "${ARCHIVE}"

[ -s "${ARCHIVE}" ] || die "arquivo de backup vazio: ${ARCHIVE}"
docker run --rm --entrypoint tar -v "${BACKUP_DIR}:/b:ro" "${HELPER_IMAGE}" tzf "/b/$(basename "${ARCHIVE}")" >/dev/null \
  || die "tarball invalido: ${ARCHIVE}"

( cd "${BACKUP_DIR}" && sha256sum "$(basename "${ARCHIVE}")" > "$(basename "${ARCHIVE}").sha256" )
chmod 600 "${ARCHIVE}" "${ARCHIVE}.sha256"

echo
echo "Backup criado: ${ARCHIVE}"
echo "SHA256:        $(cat "${ARCHIVE}.sha256")"
echo "Tamanho:       $(du -h "${ARCHIVE}" | awk '{print $1}')"
echo
echo "Guarde este arquivo FORA da VPS (contem contas, chave privada DKIM e senhas)."
