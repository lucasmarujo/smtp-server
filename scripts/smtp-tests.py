#!/usr/bin/env python3
"""Testes de conformidade SMTP/IMAP do servidor de e-mail.

Uso: python3 smtp-tests.py [host]
Retorna codigo != 0 se algum teste obrigatorio falhar.
"""
import imaplib
import smtplib
import ssl
import sys
import time

HOST = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
DOMAIN = "marujo.dev"
ACCOUNT = "hi@marujo.dev"

falhas = []


def ok(nome):
    print(f"  [ OK ] {nome}")


def fail(nome, detalhe=""):
    print(f"  [FAIL] {nome} {detalhe}")
    falhas.append(nome)


def ler_senha():
    with open("/opt/mail/secrets/hi_at_marujo.dev.txt", encoding="utf-8") as fh:
        for linha in fh:
            if linha.startswith("password:"):
                return linha.split(":", 1)[1].strip()
    raise SystemExit("senha nao encontrada em secrets/")


SENHA = ler_senha()


print("== 1. Banner / EHLO porta 25 ==")
try:
    with smtplib.SMTP(HOST, 25, timeout=15) as s:
        code, msg = s.ehlo("test.example.com")
        if code == 250 and b"STARTTLS" in msg:
            ok("EHLO responde e anuncia STARTTLS")
        else:
            fail("EHLO/STARTTLS", f"{code} {msg}")
except Exception as e:  # noqa: BLE001
    fail("conexao porta 25", str(e))


print("== 2. Open relay: remetente e destinatario externos, sem auth ==")
try:
    with smtplib.SMTP(HOST, 25, timeout=15) as s:
        s.ehlo("evil.example.com")
        time.sleep(1)
        s.mail("attacker@evil.example.com")
        code, resp = s.rcpt("victim@gmail.com")
        if code >= 500:
            ok(f"relay externo recusado ({code})")
        else:
            fail("OPEN RELAY", f"servidor aceitou RCPT externo: {code} {resp}")
except smtplib.SMTPRecipientsRefused:
    ok("relay externo recusado (RecipientsRefused)")
except smtplib.SMTPException as e:
    ok(f"relay externo recusado ({e.__class__.__name__})")
except Exception as e:  # noqa: BLE001
    fail("teste open relay", str(e))


print("== 3. Submission 587 exige STARTTLS + auth ==")
try:
    with smtplib.SMTP(HOST, 587, timeout=15) as s:
        s.ehlo("test.example.com")
        try:
            s.mail("hi@marujo.dev")
            code, resp = s.rcpt("victim@gmail.com")
            if code >= 500:
                ok(f"envio sem STARTTLS/auth recusado ({code})")
            else:
                fail("587 sem auth", f"{code} {resp}")
        except smtplib.SMTPException:
            ok("envio sem STARTTLS/auth recusado")
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        s.starttls(context=ctx)
        s.ehlo("test.example.com")
        try:
            s.login("naoexiste@marujo.dev", "senhaerrada")
            fail("587 auth invalida", "login aceito indevidamente")
        except smtplib.SMTPAuthenticationError:
            ok("credencial invalida rejeitada")
        s.login(ACCOUNT, SENHA)
        ok("login submission com credencial valida")
except Exception as e:  # noqa: BLE001
    fail("submission 587", str(e))


print("== 4. Relay negado para usuario AUTENTICADO? (deve permitir envio proprio) ==")
try:
    with smtplib.SMTP(HOST, 587, timeout=15) as s:
        s.ehlo("test.example.com")
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        s.starttls(context=ctx)
        s.login(ACCOUNT, SENHA)
        s.mail(ACCOUNT)
        code, resp = s.rcpt("victim@gmail.com")
        if code < 400:
            ok("usuario autenticado pode enviar para fora")
        else:
            fail("envio autenticado", f"{code} {resp}")
except Exception as e:  # noqa: BLE001
    fail("envio autenticado", str(e))


print("== 5. IMAPS 993 ==")
try:
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    m = imaplib.IMAP4_SSL(HOST, 993, ssl_context=ctx)
    try:
        m.login("naoexiste@marujo.dev", "senhaerrada")
        fail("IMAP auth invalida", "login aceito")
    except imaplib.IMAP4.error:
        ok("IMAP credencial invalida rejeitada")
    m.login(ACCOUNT, SENHA)
    typ, data = m.select("INBOX")
    if typ == "OK":
        ok(f"IMAP login + SELECT INBOX ({data[0].decode()} msgs)")
    else:
        fail("IMAP SELECT", str(data))
    m.logout()
except Exception as e:  # noqa: BLE001
    fail("IMAPS 993", str(e))


print()
if falhas:
    print(f"RESULTADO: {len(falhas)} falha(s): {', '.join(falhas)}")
    sys.exit(1)
print("RESULTADO: todos os testes passaram")
