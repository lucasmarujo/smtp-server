# Servidor de e-mail — marujo.dev

Servidor de e-mail proprio e isolado para o dominio `marujo.dev`, rodando em
container Docker na VPS, sem depender de SMTP/mailbox pagos.

Primeira caixa: **hi@marujo.dev**

---

## 1. Arquitetura

```
                 Internet
                    │
   ┌────────────────┼───────────────────────────┐
   │  VPS (Ubuntu 24.04 · 76.13.167.76)          │
   │                                            │
   │   Caddy (/opt/proxy)                        │
   │     :80/:443  ── reverse proxy dos outros   │
   │     projetos + emite o cert LE de           │
   │     mail.marujo.dev (compartilhado ro)      │
   │                                            │
   │   Container "mail" (/opt/mail)              │
   │     docker-mailserver 15.1.0                │
   │     ├─ Postfix   :25  (MX, servidor→servidor)
   │     ├─ Postfix   :587 (submission, auth+TLS)│
   │     ├─ Dovecot   :993 (IMAPS)               │
   │     ├─ Rspamd    (antispam + assinatura DKIM,│
   │     │             checagem SPF/DKIM/DMARC)  │
   │     ├─ Fail2ban  (brute force)              │
   │     └─ Redis     (estado do Rspamd)         │
   │                                            │
   │   Volumes persistentes em                   │
   │     /opt/mail/docker-data/dms/              │
   └────────────────────────────────────────────┘
```

- Um unico container (imagem `docker-mailserver`) agrega Postfix + Dovecot +
  Rspamd, que e a implementacao de referencia dessa stack. A separacao logica
  entre os servicos e mantida; a persistencia e por diretorio.
- Isolado dos demais projetos: rede Docker propria (`mail_default`), sem
  `mynetworks`, sem compartilhar volumes.
- ClamAV, Amavis e SpamAssassin desligados (Rspamd cobre antispam; a VPS tem
  RAM limitada). Reative via `.env` se quiser.

### Mapa de diretorios

| Caminho | Conteudo |
|---|---|
| `docker-compose.yml` | definicao do servico (sem secrets) |
| `.env` | variaveis e flags (perm. `600`, fora do git) |
| `.env.example` | modelo versionado |
| `config/` | material de apoio: snippet do Caddy, registros DNS |
| `config/ssl/` | certificado self-signed temporario (fallback) |
| `docker-data/dms/config/` | contas, aliases, chaves DKIM, overrides Rspamd/Dovecot |
| `docker-data/dms/mail-data/` | mailboxes (Maildir) — **os e-mails** |
| `docker-data/dms/mail-state/` | estado (Redis, Rspamd, Fail2ban, logs rotacionados) |
| `docker-data/dms/mail-logs/` | logs do Postfix/Dovecot/Rspamd |
| `secrets/` | senhas geradas das contas (perm. `700`, fora do git) |
| `backups/` | tarballs de backup (fora do git) |
| `scripts/` | manutencao (abaixo) |

---

## 2. Servicos e portas

| Porta | Servico | Uso | TLS |
|---|---|---|---|
| 25  | Postfix smtpd     | recepcao servidor→servidor (MX). Sem AUTH, sem relay. | STARTTLS oportunista |
| 587 | Postfix submission | envio autenticado pelos clientes | STARTTLS **obrigatorio** |
| 993 | Dovecot imap-login | leitura das caixas | TLS implicito **obrigatorio** |

Portas 110/143/465/995/4190 existem no container mas **nao** sao publicadas.
Interface web do Rspamd (`:11334`) fica so na rede interna do container.

---

## 3. Subir / descer / atualizar

```bash
cd /opt/mail

docker compose up -d          # subir
docker compose ps             # status
docker compose down           # descer (mantem volumes/dados)
docker compose restart mail   # reiniciar

# Atualizar a imagem:
#   1. edite DMS_IMAGE no .env (ex.: mailserver/docker-mailserver:15.2.0)
#   2.
docker compose pull
docker compose up -d
./scripts/healthcheck.sh
#   Consulte o CHANGELOG do docker-mailserver antes de subir major.
```

> Use sempre `docker compose down && up -d` (nao `restart`) apos mudar `.env` ou
> arquivos em `docker-data/dms/config/` — o `restart` pode duplicar linhas de
> configuracao regeneradas.

---

## 4. Logs

```bash
docker compose logs -f mail                       # log do container
docker exec mail tail -f /var/log/mail/mail.log   # Postfix + Dovecot
docker exec mail tail -f /var/log/mail/rspamd.log # Rspamd

# Filtros uteis
docker exec mail grep -i 'reject'      /var/log/mail/mail.log   # rejeicoes
docker exec mail grep -i 'sasl'        /var/log/mail/mail.log   # autenticacao
docker exec mail grep -i 'status=sent' /var/log/mail/mail.log   # entregas
docker exec mail grep -Ei 'tls|ssl'    /var/log/mail/mail.log   # TLS
docker exec mail fail2ban-client status postfix
```

Rotacao: logs do container limitados a `10m x 5` arquivos (`docker-compose.yml`);
logs internos rotacionados pelo `logrotate` do proprio DMS.

---

## 5. Adicionar caixa postal

```bash
./scripts/add-mailbox.sh contato@marujo.dev
# senha aleatoria gerada e salva em secrets/contato_marujo.dev.txt
```

Manual, equivalente:

```bash
docker exec -ti mail setup email add contato@marujo.dev
docker exec -ti mail setup email list
```

Novo **dominio**: adicione MX/SPF/DMARC desse dominio e gere DKIM
(`./scripts/dkim-show.sh --generate outrodominio.com`).

---

## 6. Remover caixa postal

```bash
./scripts/del-mailbox.sh contato@marujo.dev            # remove a conta, preserva os arquivos
./scripts/del-mailbox.sh contato@marujo.dev --purge    # remove tambem a mailbox em disco
```

---

## 7. Alterar senha

```bash
./scripts/passwd-mailbox.sh hi@marujo.dev            # nova senha aleatoria -> secrets/
./scripts/passwd-mailbox.sh hi@marujo.dev --prompt   # digitar a senha
```

Manual: `docker exec -ti mail setup email update hi@marujo.dev`

---

## 8. DKIM — gerar / renovar / ver

```bash
./scripts/dkim-show.sh                          # mostra o TXT atual
./scripts/dkim-show.sh --generate marujo.dev    # gera nova chave (selector 'mail') e reinicia
```

Apos gerar, publique/atualize o TXT `mail._domainkey.marujo.dev`
(ver `config/dns-records.md`). Rotacione a chave ~1x/ano: gere, publique o novo
TXT, aguarde a propagacao, mantenha o antigo por alguns dias e depois remova.

---

## 9. Backup

```bash
./scripts/backup.sh
# -> backups/mail-backup-AAAAMMDD-HHMMSS.tar.gz (+ .sha256)
```

Inclui: `docker-compose.yml`, `.env`, `config/` (inclui o cert self-signed de
fallback), `scripts/`, `docker-data/dms/config` (contas, aliases, chaves DKIM,
overrides), `docker-data/dms/mail-data` (todas as mailboxes) e `secrets/`.
Nao inclui `docker-data/dms/mail-state/` (estado de runtime regenerado pelo
container: spool do Postfix, base do Fail2ban, cache do Rspamd).

O script **pausa o container** durante o `tar` para um snapshot consistente e
sobe de novo ao final. **Nao** apaga backups antigos automaticamente:

```bash
./scripts/backup.sh --prune 30   # remove backups com mais de 30 dias (manual)
```

Copie os tarballs para fora da VPS (contem senhas e chave privada DKIM).
Sugestao de agendamento (crontab do usuario `lucas`):

```
15 3 * * *  /opt/mail/scripts/backup.sh >> /opt/mail/backups/backup.log 2>&1
```

---

## 10. Restaurar backup

```bash
./scripts/restore.sh backups/mail-backup-AAAAMMDD-HHMMSS.tar.gz
```

Verifica o SHA256, salva um snapshot de seguranca em `backups/pre-restore-*`,
extrai por cima da instalacao e sobe o container. Rode o healthcheck depois.

---

## 11. Verificar saude

```bash
./scripts/healthcheck.sh            # completo
./scripts/healthcheck.sh --quiet    # so problemas (para cron/alerta)
```

Codigos de saida: `0` OK · `2` OK com avisos · `1` falha.
Checa container, Postfix/Dovecot/Rspamd/Fail2ban, portas 25/587/993, banner,
certificado TLS (e validade), fila do Postfix, chave DKIM, DNS
(A/MX/SPF/DKIM/DMARC/PTR) e uso de disco.

Testes de conformidade SMTP/IMAP (inclui teste de **open relay**):

```bash
python3 scripts/smtp-tests.py
```

---

## 12. Configuracao dos clientes

```
E-mail:    hi@marujo.dev
Usuario:   hi@marujo.dev          (endereco completo)
Senha:     (secrets/hi_at_marujo.dev.txt)

IMAP:
  servidor: mail.marujo.dev
  porta:    993
  seguranca: SSL/TLS

SMTP:
  servidor: mail.marujo.dev
  porta:    587
  seguranca: STARTTLS
  autenticacao: normal (usuario + senha), obrigatoria
```

Enquanto o certificado for self-signed (fase inicial), o cliente vai avisar sobre
certificado nao confiavel. Depois de ativar o Let's Encrypt (secao 13) o aviso
some.

---

## 13. Registros DNS e TLS

### DNS

Ver `config/dns-records.md` para a tabela completa e os valores exatos.
Resumo do que falta criar em `marujo.dev`:

```
marujo.dev.                  MX    10 mail.marujo.dev.
marujo.dev.                  TXT   "v=spf1 mx -all"
_dmarc.marujo.dev.           TXT   "v=DMARC1; p=none; rua=mailto:hi@marujo.dev"
mail._domainkey.marujo.dev.  TXT   "v=DKIM1; k=rsa; p=MIIBIjANBgkq...IDAQAB"   (valor completo em config/dns-records.md)
```

`mail.marujo.dev A 76.13.167.76` ja existe.

### PTR (reverse DNS)

Ajustar no painel da Hostinger (hPanel -> VPS -> rDNS):
`76.13.167.76 -> mail.marujo.dev`. Nao e alteravel a partir da VPS.

### TLS via Let's Encrypt (usa o Caddy ja existente)

1. Confirme que `mail.marujo.dev A` aponta para a VPS (ja OK).
2. Adicione ao `/opt/proxy/Caddyfile` o bloco de
   `config/caddy-mail.snippet.Caddyfile`.
3. Recarregue o Caddy sem downtime:
   ```bash
   docker exec -w /etc/caddy caddy caddy reload
   ```
4. Aguarde o Caddy emitir o certificado:
   ```bash
   docker exec caddy ls /data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/mail.marujo.dev/
   ```
   (se o Caddy usar o ZeroSSL como fallback, o diretorio muda —
   ajuste `SSL_CERT_PATH`/`SSL_KEY_PATH` no `.env` conforme o caminho real.)
5. No `.env`: `SSL_TYPE=self-signed` -> `SSL_TYPE=manual`.
6. `cd /opt/mail && docker compose up -d && ./scripts/healthcheck.sh`

Renovacao: automatica pelo Caddy. O container detecta a troca do arquivo e
recarrega Postfix/Dovecot sozinho.

---

## 14. Troubleshooting

| Sintoma | Onde olhar |
|---|---|
| Container reinicia em loop | `docker compose logs mail` — geralmente TLS (arquivo de cert ausente) ou nenhuma conta criada |
| `TLS Setup ... does not exist` | com `SSL_TYPE=self-signed` os arquivos tem que estar em `config/ssl/`; com `manual`, confira o caminho do cert do Caddy |
| Cliente nao autentica no 587 | precisa ser STARTTLS + usuario = endereco completo; veja `grep sasl /var/log/mail/mail.log` |
| E-mail enviado cai em spam no Gmail | PTR, SPF, DKIM e DMARC publicados? Teste em https://www.mail-tester.com e veja o header `Authentication-Results` |
| Nao recebe e-mail externo | MX publicado? porta 25 de entrada liberada no firewall? `docker exec mail mailq` |
| `Connection refused` na porta 25/587/993 | container no ar? regra UFW? `./scripts/healthcheck.sh` |
| Fila crescendo | `docker exec mail mailq`; `docker exec mail postqueue -f` forca reentrega; ver destino em `mail.log` |
| Ver por que uma mensagem foi barrada pelo Rspamd | `docker exec mail rspamc stat`; `/var/log/mail/rspamd.log` |
| IP em blocklist | consulte https://multirbl.valli.org ; peca delisting; melhore aquecimento/volume |
| Rspamd web UI | `ssh -L 11334:127.0.0.1:11334 lucas@76.13.167.76` depois `docker exec mail ...` ou publique com auth |

Comandos de diagnostico:

```bash
docker exec mail postconf -n                 # config efetiva do Postfix
docker exec mail doveconf -n                 # config efetiva do Dovecot
docker exec mail setup email list            # contas
docker exec mail supervisorctl status        # servicos internos
```

---

## 15. Atualizar os containers

```bash
cd /opt/mail
# 1. backup antes
./scripts/backup.sh
# 2. ajуste a tag em .env (DMS_IMAGE=mailserver/docker-mailserver:X.Y.Z)
# 3.
docker compose pull
docker compose up -d
# 4. valida
./scripts/healthcheck.sh
python3 scripts/smtp-tests.py
```

Ler o CHANGELOG do docker-mailserver
(https://github.com/docker-mailserver/docker-mailserver/blob/master/CHANGELOG.md)
antes de mudanca de major. Rollback: volte a tag anterior no `.env` +
`docker compose up -d` (ou restaure o backup).

O Caddy e o Redis do Rspamd atualizam junto com suas respectivas imagens
(`caddy:2-alpine` fora deste projeto; Redis embutido no DMS).

---

## 16. Riscos de operar um servidor de e-mail proprio

- **Entregabilidade / reputacao.** IP novo comeca sem reputacao. Sem PTR, SPF,
  DKIM e DMARC corretos, mensagens vao para spam ou sao recusadas. Volume
  irregular ou picos parecem spam. Aquecer o IP gradualmente.
- **Blocklists.** Um unico envio ruim (conta comprometida, formulario abusado)
  pode colocar o IP em RBLs; sair delas e lento.
- **Porta 25.** Alguns provedores bloqueiam a 25 de saida — aqui esta **liberada**
  (testado). Se a Hostinger reverter isso, o envio direto para outros servidores
  para de funcionar e seria preciso um smarthost/relay.
- **Disponibilidade.** Se a VPS cair, e-mails de entrada ficam na fila do
  remetente (normalmente reentregues por ate ~5 dias) e voce fica sem acesso a
  caixa. Sem redundancia de MX.
- **Manutencao continua.** Patches de seguranca, renovacao/rotacao de chaves,
  monitorar filas, relatorios DMARC, mudancas de politica dos grandes provedores.
- **Seguranca.** Servico exposto na internet (25/587/993). Fail2ban e TLS
  mitigam, mas exige acompanhar logs e atualizar a imagem.
- **Backup e o que esta em jogo.** Perder `docker-data/` = perder e-mails. Backup
  testado e off-site e obrigatorio.
- **Legal / abuso.** Voce e responsavel pelo trafego do seu IP. Configure
  `abuse@`/`postmaster@` e responda a reclamacoes.

Mitigacao pratica: manter DMARC em `p=none` ate os relatorios ficarem limpos,
subir para `quarantine` e depois `reject`; healthcheck no cron; backup diario
off-site; considerar um MX secundario / servico de backup MX no futuro.
