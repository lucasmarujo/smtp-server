#!/usr/bin/env bash
# Altera a senha de uma caixa postal.
#   ./passwd-mailbox.sh usuario@marujo.dev            -> gera senha aleatoria
#   ./passwd-mailbox.sh usuario@marujo.dev --prompt   -> pede a senha via stdin
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ADDR="${1:-}"
MODE="${2:-}"
[ -n "${ADDR}" ] || die "uso: $0 endereco@dominio [--prompt]"
require_container

SECRETS_DIR="${MAIL_DIR}/secrets"
mkdir -p "${SECRETS_DIR}"; chmod 700 "${SECRETS_DIR}"
SAFE_NAME="$(echo "${ADDR}" | tr '@/' '_')"
SECRET_FILE="${SECRETS_DIR}/${SAFE_NAME}.txt"

if [ "${MODE}" = "--prompt" ]; then
  read -r -s -p "Nova senha: " PW; echo
  read -r -s -p "Confirme:   " PW2; echo
  [ "${PW}" = "${PW2}" ] || die "senhas diferentes"
else
  PW="$(openssl rand -base64 21)"
fi

printf '%s\n%s\n' "${PW}" "${PW}" | docker exec -i "${CONTAINER}" setup email update "${ADDR}"
( umask 077 && printf 'account: %s\npassword: %s\nupdated: %s\n' "${ADDR}" "${PW}" "$(date -Is)" > "${SECRET_FILE}" )
unset PW PW2 2>/dev/null || true

echo "Senha atualizada. Registro em: ${SECRET_FILE}"
