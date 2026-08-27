#!/usr/bin/env bash
# Verificacao de saude do servidor de e-mail.
# Retorna 0 se tudo OK, 1 se houver falha, 2 se apenas avisos.
#
#   ./healthcheck.sh            saida normal
#   ./healthcheck.sh --quiet    so mostra problemas
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

QUIET="${1:-}"
FAIL=0
WARN=0

pass() { [ "${QUIET}" = "--quiet" ] || echo "  [ OK ]  $*"; }
warn() { echo "  [WARN]  $*"; WARN=1; }
err()  { echo "  [FAIL]  $*"; FAIL=1; }

MAIL_HOSTNAME="$(grep -E '^MAIL_HOSTNAME=' "${MAIL_DIR}/.env" | cut -d= -f2)"
MAIL_DOMAIN="$(grep -E '^MAIL_DOMAIN=' "${MAIL_DIR}/.env" | cut -d= -f2)"
SSL_TYPE="$(grep -E '^SSL_TYPE=' "${MAIL_DIR}/.env" | cut -d= -f2)"
PUB_IP="$(curl -4 -s --max-time 8 https://api.ipify.org || echo '')"

echo "== 1. Container =="
STATE="$(docker inspect -f '{{.State.Status}}' "${CONTAINER}" 2>/dev/null || echo missing)"
HEALTH="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "${CONTAINER}" 2>/dev/null || echo n/a)"
if [ "${STATE}" = "running" ] && { [ "${HEALTH}" = "healthy" ] || [ "${HEALTH}" = "n/a" ]; }; then
  pass "container '${CONTAINER}' running (health: ${HEALTH})"
else
  err "container '${CONTAINER}' state=${STATE} health=${HEALTH}"
  echo "RESULTADO: FALHA"; exit 1
fi

echo "== 2. Servicos internos (supervisorctl) =="
SVC="$(docker exec "${CONTAINER}" supervisorctl status 2>/dev/null || true)"
for s in postfix dovecot rspamd fail2ban; do
  line="$(echo "${SVC}" | grep -E "^${s}\b" || true)"
  if echo "${line}" | grep -q RUNNING; then
    pass "${s} RUNNING"
  else
    err "${s} nao esta RUNNING (${line:-ausente})"
  fi
done

echo "== 3. Portas publicas =="
for p in 25 587 993; do
  if (exec 3<>"/dev/tcp/127.0.0.1/${p}") 2>/dev/null; then
    pass "porta ${p} aceitando conexao"
    exec 3>&- 2>/dev/null || true
  else
    err "porta ${p} nao responde"
  fi
done

echo "== 4. Banner SMTP / HELO =="
BANNER="$(printf 'QUIT\r\n' | timeout 8 nc -w5 127.0.0.1 25 | head -n1 || true)"
if echo "${BANNER}" | grep -q "${MAIL_HOSTNAME}"; then
  pass "banner anuncia ${MAIL_HOSTNAME}"
else
  warn "banner inesperado: ${BANNER}"
fi

echo "== 5. TLS =="
CERT="$(echo | timeout 8 openssl s_client -connect 127.0.0.1:993 2>/dev/null | openssl x509 -noout -subject -enddate 2>/dev/null || true)"
if echo "${CERT}" | grep -q "${MAIL_HOSTNAME}"; then
  END="$(echo "${CERT}" | sed -n 's/notAfter=//p')"
  END_TS="$(date -d "${END}" +%s 2>/dev/null || echo 0)"
  NOW_TS="$(date +%s)"
  DAYS=$(( (END_TS - NOW_TS) / 86400 ))
  if [ "${SSL_TYPE}" = "self-signed" ]; then
    warn "certificado self-signed em uso (validade ${DAYS}d) - trocar para Let's Encrypt em producao"
  elif [ "${DAYS}" -lt 10 ]; then
    err "certificado expira em ${DAYS} dias"
  else
    pass "certificado valido para ${MAIL_HOSTNAME} (expira em ${DAYS}d)"
  fi
else
  err "nao foi possivel validar o certificado TLS em 993"
fi

echo "== 6. Fila do Postfix =="
QLEN="$(docker exec "${CONTAINER}" sh -c 'mailq | tail -n1' 2>/dev/null || true)"
if echo "${QLEN}" | grep -qi 'empty'; then
  pass "fila vazia"
else
  DEFERRED="$(docker exec "${CONTAINER}" sh -c 'postqueue -p | grep -c "^[A-F0-9]"' 2>/dev/null || echo '?')"
  warn "fila com mensagens pendentes (${DEFERRED}) - verifique com: docker exec ${CONTAINER} mailq"
fi

echo "== 7. Rspamd =="
if docker exec "${CONTAINER}" rspamc stat >/dev/null 2>&1; then
  pass "rspamd respondendo (rspamc stat)"
else
  err "rspamd nao respondeu a rspamc stat"
fi
DKIM_KEY="$(ls "${MAIL_DIR}"/docker-data/dms/config/rspamd/dkim/*private* 2>/dev/null | head -n1 || true)"
[ -n "${DKIM_KEY}" ] && pass "chave DKIM presente ($(basename "${DKIM_KEY}"))" || err "chave DKIM ausente"

echo "== 8. DNS publico =="
dns_txt() { dig +short "$1" "$2" @1.1.1.1 2>/dev/null | tr -d '"' | tr -s ' '; }
A_REC="$(dig +short "${MAIL_HOSTNAME}" A @1.1.1.1 2>/dev/null)"
[ -n "${A_REC}" ] && pass "A ${MAIL_HOSTNAME} -> ${A_REC}" || err "A ${MAIL_HOSTNAME} ausente"
if [ -n "${PUB_IP}" ] && [ "${A_REC}" != "${PUB_IP}" ]; then
  warn "A (${A_REC}) difere do IP publico atual (${PUB_IP})"
fi
MX_REC="$(dig +short "${MAIL_DOMAIN}" MX @1.1.1.1 2>/dev/null)"
echo "${MX_REC}" | grep -q "${MAIL_HOSTNAME}" && pass "MX ${MAIL_DOMAIN} -> ${MX_REC}" || err "MX ${MAIL_DOMAIN} ausente/incorreto"
SPF="$(dns_txt "${MAIL_DOMAIN}" TXT | grep -i 'v=spf1' || true)"
[ -n "${SPF}" ] && pass "SPF: ${SPF}" || err "SPF (TXT v=spf1) ausente em ${MAIL_DOMAIN}"
DMARC="$(dns_txt "_dmarc.${MAIL_DOMAIN}" TXT | grep -i 'v=DMARC1' || true)"
[ -n "${DMARC}" ] && pass "DMARC: ${DMARC}" || err "DMARC ausente em _dmarc.${MAIL_DOMAIN}"
DKIM_DNS="$(dns_txt "mail._domainkey.${MAIL_DOMAIN}" TXT | grep -i 'v=DKIM1' || true)"
[ -n "${DKIM_DNS}" ] && pass "DKIM DNS publicado" || err "DKIM ausente em mail._domainkey.${MAIL_DOMAIN}"
if [ -n "${PUB_IP}" ]; then
  PTR=""
  for res in 1.1.1.1 8.8.8.8 9.9.9.9; do
    p="$(dig +short -x "${PUB_IP}" @"${res}" 2>/dev/null)"
    PTR="${PTR}${p}"
    echo "${p}" | grep -q "${MAIL_HOSTNAME}" && PTR_OK=1
  done
  if [ -n "${PTR_OK:-}" ]; then
    pass "PTR ${PUB_IP} -> ${MAIL_HOSTNAME}"
  else
    warn "PTR ainda = ${PTR:-vazio} (alvo: ${MAIL_HOSTNAME}.) - se ja configurou no hPanel, aguarde a propagacao (ate algumas horas)"
  fi
fi

echo "== 9. Webmail (Roundcube) =="
RC_STATE="$(docker inspect -f '{{.State.Status}}' roundcube 2>/dev/null || echo missing)"
RC_HEALTH="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' roundcube 2>/dev/null || echo n/a)"
if [ "${RC_STATE}" = "missing" ]; then
  warn "container 'roundcube' nao existe (webmail nao instalado)"
elif [ "${RC_STATE}" = "running" ] && { [ "${RC_HEALTH}" = "healthy" ] || [ "${RC_HEALTH}" = "starting" ] || [ "${RC_HEALTH}" = "n/a" ]; }; then
  pass "container 'roundcube' running (health: ${RC_HEALTH})"
  RC_LOCAL="$(docker exec roundcube sh -c 'curl -s -o /dev/null -w "%{http_code}" http://localhost/' 2>/dev/null || echo 000)"
  [ "${RC_LOCAL}" = "200" ] && pass "Roundcube responde HTTP 200 (interno)" || warn "Roundcube HTTP interno = ${RC_LOCAL}"
  WM_HOST="webmail.${MAIL_DOMAIN}"
  WM_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${WM_HOST}/" 2>/dev/null || echo 000)"
  [ "${WM_CODE}" = "200" ] && pass "https://${WM_HOST} -> 200" || err "https://${WM_HOST} -> ${WM_CODE}"
  if echo | openssl s_client -connect "${WM_HOST}:443" -servername "${WM_HOST}" 2>/dev/null \
       | openssl x509 -noout -checkend 864000 >/dev/null 2>&1; then
    pass "certificado de ${WM_HOST} valido (>10d)"
  else
    warn "certificado de ${WM_HOST} perto de expirar ou invalido"
  fi
  if docker exec roundcube test -f /var/www/html/plugins/gravatar/gravatar.php 2>/dev/null \
       && docker exec roundcube grep -q "'gravatar'" /var/www/html/config/config.docker.inc.php 2>/dev/null; then
    pass "plugin 'gravatar' instalado e ativo (avatares)"
  else
    warn "plugin 'gravatar' ausente ou fora de ROUNDCUBEMAIL_PLUGINS"
  fi
  GRAV_CODE="$(docker exec roundcube curl -s -o /dev/null -w '%{http_code}' --max-time 10 'https://www.gravatar.com/avatar/0?d=404' 2>/dev/null || echo 000)"
  if [ "${GRAV_CODE}" = "404" ] || [ "${GRAV_CODE}" = "200" ]; then
    pass "container alcanca gravatar.com (avatares carregam)"
  else
    warn "container nao alcanca gravatar.com (HTTP ${GRAV_CODE}) - avatares nao vao carregar"
  fi
else
  err "container 'roundcube' state=${RC_STATE} health=${RC_HEALTH}"
fi

echo "== 10. Armazenamento =="
USE="$(df -P "${MAIL_DIR}" | awk 'NR==2{gsub("%","",$5); print $5}')"
if [ "${USE}" -ge 90 ]; then err "disco em ${USE}% de uso"
elif [ "${USE}" -ge 80 ]; then warn "disco em ${USE}% de uso"
else pass "disco em ${USE}% de uso"; fi
MAILSIZE="$(du -sh "${MAIL_DIR}/docker-data/dms/mail-data" 2>/dev/null | awk '{print $1}')"
pass "tamanho das mailboxes: ${MAILSIZE:-?}"

echo
if [ "${FAIL}" -ne 0 ]; then echo "RESULTADO: FALHA (ha itens [FAIL])"; exit 1; fi
if [ "${WARN}" -ne 0 ]; then echo "RESULTADO: OK COM AVISOS"; exit 2; fi
echo "RESULTADO: OK"
