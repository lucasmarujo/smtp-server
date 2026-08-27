#!/usr/bin/env bash
# Cria uma nova caixa postal.
#   ./add-mailbox.sh usuario@marujo.dev
# A senha e gerada aleatoriamente e gravada em secrets/ com permissao 600.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ADDR="${1:-}"
[ -n "${ADDR}" ] || die "uso: $0 endereco@dominio"
require_container

SECRETS_DIR="${MAIL_DIR}/secrets"
mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"
SAFE_NAME="$(echo "${ADDR}" | tr '@/' '_')"
SECRET_FILE="${SECRETS_DIR}/${SAFE_NAME}.txt"

PW="$(openssl rand -base64 21)"
( umask 077 && printf 'account: %s\npassword: %s\ncreated: %s\n' "${ADDR}" "${PW}" "$(date -Is)" > "${SECRET_FILE}" )

printf '%s\n%s\n' "${PW}" "${PW}" | docker exec -i "${CONTAINER}" setup email add "${ADDR}"
unset PW

echo
echo "Caixa criada: ${ADDR}"
echo "Senha salva em: ${SECRET_FILE}"
echo "Lembre de publicar/ajustar SPF/DMARC se for um novo dominio."
