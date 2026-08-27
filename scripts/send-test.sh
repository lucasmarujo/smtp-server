#!/usr/bin/env bash
# Envia um e-mail de teste autenticado a partir de hi@marujo.dev.
#
#   ./send-test.sh destino@exemplo.com
#   ./send-test.sh destino@exemplo.com "Assunto opcional"
#
# Usa submission (587 + STARTTLS + AUTH) com a senha de secrets/.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

DEST="${1:-}"
SUBJECT="${2:-Teste de envio - marujo.dev}"
[ -n "${DEST}" ] || die "uso: $0 destino@exemplo.com [assunto]"
require_container

FROM="hi@marujo.dev"
SECRET_FILE="${MAIL_DIR}/secrets/hi_at_marujo.dev.txt"
[ -f "${SECRET_FILE}" ] || die "senha nao encontrada em ${SECRET_FILE}"
PW="$(grep '^password:' "${SECRET_FILE}" | cut -d' ' -f2-)"

python3 - "$FROM" "$PW" "$DEST" "$SUBJECT" <<'PY'
import smtplib, ssl, sys, time, email.utils
frm, pw, dest, subject = sys.argv[1:5]
msg = (
    f"From: marujo.dev <{frm}>\r\n"
    f"To: {dest}\r\n"
    f"Subject: {subject}\r\n"
    f"Date: {email.utils.formatdate(localtime=True)}\r\n"
    f"Message-ID: {email.utils.make_msgid(domain='marujo.dev')}\r\n"
    "Content-Type: text/plain; charset=utf-8\r\n"
    "\r\n"
    "Este e um e-mail de teste enviado pelo servidor mail.marujo.dev.\r\n"
    f"Horario: {time.strftime('%Y-%m-%d %H:%M:%S %z')}\r\n"
)
ctx = ssl.create_default_context()
s = smtplib.SMTP("mail.marujo.dev", 587, timeout=30)
s.starttls(context=ctx)
s.login(frm, pw)
s.sendmail(frm, [dest], msg)
s.quit()
print(f"OK: mensagem aceita para {dest}")
PY
unset PW

echo
echo "Acompanhe a entrega:"
echo "  docker exec ${CONTAINER} tail -n 20 /var/log/mail/mail.log | grep -i '${DEST%%@*}'"
echo "  docker exec ${CONTAINER} mailq        # se ficou em fila"
