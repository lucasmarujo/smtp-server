#!/usr/bin/env bash
# Backup completo do servidor de e-mail.
# Gera um tarball CRIPTOGRAFADO (gpg, AES256 simetrico) em backups/ com:
# configuracao, contas, aliases, mailboxes, chaves DKIM, certificado TLS de
# fallback, scripts e .env. NAO remove backups antigos automaticamente.
#
#   ./backup.sh                 cria um backup
#   ./backup.sh --prune <dias>  remove backups mais antigos que <dias> (manual)
#
# O tar roda dentro de um container efemero como root (a imagem do DMS) porque
# parte dos dados em docker-data/ pertence ao root. NAO inclui
# docker-data/dms/mail-state/ (estado de runtime regenerado pelo container).
#
# A criptografia usa a passphrase em secrets/backup-passphrase.txt. Guarde
# uma copia dela FORA da VPS - sem ela os backups sao irrecuperaveis.
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

PASSPHRASE_FILE="${MAIL_DIR}/secrets/backup-passphrase.txt"
[ -s "${PASSPHRASE_FILE}" ] || die "passphrase de backup ausente: ${PASSPHRASE_FILE}"

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

ENCRYPTED="${ARCHIVE}.gpg"
gpg --batch --yes --pinentry-mode loopback \
  --passphrase-file "${PASSPHRASE_FILE}" \
  --symmetric --cipher-algo AES256 \
  -o "${ENCRYPTED}" "${ARCHIVE}" \
  || die "falha ao criptografar: ${ARCHIVE}"
rm -f "${ARCHIVE}"

( cd "${BACKUP_DIR}" && sha256sum "$(basename "${ENCRYPTED}")" > "$(basename "${ENCRYPTED}").sha256" )
chmod 600 "${ENCRYPTED}" "${ENCRYPTED}.sha256"

echo
echo "Backup criado: ${ENCRYPTED}"
echo "SHA256:        $(cat "${ENCRYPTED}.sha256")"
echo "Tamanho:       $(du -h "${ENCRYPTED}" | awk '{print $1}')"
echo
echo "Guarde este arquivo FORA da VPS. Para restaurar, descriptografe primeiro:"
echo "  gpg --batch --pinentry-mode loopback --passphrase-file secrets/backup-passphrase.txt -d '${ENCRYPTED}' > backup.tar.gz"
