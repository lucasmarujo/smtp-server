#!/usr/bin/env bash
# Restaura um backup gerado por backup.sh.
#   ./restore.sh backups/mail-backup-AAAAMMDD-HHMMSS.tar.gz
#
# Sobrescreve config/, scripts/, secrets/, .env e
# docker-data/dms/{config,mail-data}. Pede confirmacao antes de aplicar.
# A extracao roda como root (container efemero) para preservar permissoes.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ARCHIVE="${1:-}"
[ -n "${ARCHIVE}" ] || die "uso: $0 caminho/do/backup.tar.gz"
[ -f "${ARCHIVE}" ] || die "arquivo nao encontrado: ${ARCHIVE}"
ARCHIVE="$(cd "$(dirname "${ARCHIVE}")" && pwd)/$(basename "${ARCHIVE}")"

if [ -f "${ARCHIVE}.sha256" ]; then
  echo "Verificando integridade..."
  ( cd "$(dirname "${ARCHIVE}")" && sha256sum -c "$(basename "${ARCHIVE}").sha256" ) || die "checksum invalido"
fi

HELPER_IMAGE="$(grep -E '^DMS_IMAGE=' "${MAIL_DIR}/.env" | cut -d= -f2)"

echo "Conteudo do backup (primeiras linhas):"
docker run --rm --entrypoint tar -v "$(dirname "${ARCHIVE}"):/b:ro" "${HELPER_IMAGE}" \
  tzf "/b/$(basename "${ARCHIVE}")" | sed 's/^/  /' | head -n 15
echo "  ..."
read -r -p "Restaurar sobre a instalacao atual em ${MAIL_DIR}? (digite 'sim'): " CONF
[ "${CONF}" = "sim" ] || die "cancelado"

if docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null | grep -q true; then
  "${COMPOSE[@]}" down
fi

SAFETY="${MAIL_DIR}/backups/pre-restore-$(date +%Y%m%d-%H%M%S).tar.gz"
echo "Salvando estado atual em ${SAFETY} ..."
docker run --rm --entrypoint tar -v "${MAIL_DIR}:/data:ro" "${HELPER_IMAGE}" \
  czf - --ignore-failed-read -C /data docker-data/dms/config docker-data/dms/mail-data secrets .env > "${SAFETY}" || true
chmod 600 "${SAFETY}" 2>/dev/null || true

echo "Extraindo backup..."
docker run --rm --entrypoint tar \
  -v "${MAIL_DIR}:/data" -v "$(dirname "${ARCHIVE}"):/b:ro" \
  "${HELPER_IMAGE}" \
  xzf "/b/$(basename "${ARCHIVE}")" -C /data

chmod 600 "${MAIL_DIR}/.env" 2>/dev/null || true
chmod 700 "${MAIL_DIR}/secrets" 2>/dev/null || true

echo "Subindo container..."
"${COMPOSE[@]}" up -d

echo "Restauracao concluida. Rode ./scripts/healthcheck.sh para validar."
