# Registros DNS - marujo.dev

IP publico da VPS (IPv4): **76.13.167.76**
IPv6 detectado: `2a02:4780:6e:cbb5::1` — **nao publicar AAAA** por enquanto (ver nota no fim).

| Nome (host)                       | Tipo | Valor / conteudo                                   | TTL  | Status |
|-----------------------------------|------|---------------------------------------------------|------|--------|
| `mail.marujo.dev`                 | A    | `76.13.167.76`                                     | 3600 | OK (existe) |
| `webmail.marujo.dev`              | A    | `76.13.167.76`                                     | 3600 | OK (wildcard `*.marujo.dev`) |
| `marujo.dev`                      | MX   | `10 mail.marujo.dev`                               | 3600 | OK (publicado) |
| `marujo.dev`                      | TXT  | `v=spf1 mx -all`                                   | 3600 | OK (publicado 2026-08-29) |
| `_dmarc.marujo.dev`               | TXT  | `v=DMARC1; p=none; rua=mailto:hi@marujo.dev`       | 3600 | OK (publicado) |
| `mail._domainkey.marujo.dev`      | TXT  | valor DKIM abaixo                                  | 3600 | OK (publicado) |
| PTR `76.13.167.76`                | -    | `mail.marujo.dev` (no hPanel, nao no DNS)          | -    | OK (configurado) |

## DKIM (selector `mail`)

Nome: `mail._domainkey.marujo.dev`
Tipo: `TXT`
Valor (uma unica string; se o painel exigir, quebre em pedacos de 255 caracteres):

```
v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzk1VRm9l/OUZLzSMvlWy1uua0sUmXyazFhsN+aCcDFK4KzaFXGsPFiI3Dw5EEZFCBkvqn6Vt3LH4MCgAMDOSJzo2QJ+yRNAUqPDH+yUh3WpowewyadCishzcxweGNW6BXccIjI0vsgyEVJcS2AL5yIoJln/U6sjInn/Qq9Is9Asn9Z8u0JHupkofPc+9Of3raQ5z7QX3z4GrpuKDjHRdRMw00k+GsJqQUX6J+Kp85xt0yAZsgrRnaunXDSeuuaNX/TU//T/7tH4B9CEvLMtlcqLuOLaNZ1vnsrx+94iTYFxVzphE+ddrbA72A95kskFk7RkfM+ODMiaIEV5E2bPC3wIDAQAB
```

Regenerar / reexibir: `./scripts/dkim-show.sh`

## PTR / Reverse DNS  (NAO alteravel pela VPS)

Atual: `76.13.167.76 -> srv1844440.hstgr.cloud`
Desejado: `76.13.167.76 -> mail.marujo.dev`

Configurar no painel da Hostinger: **hPanel -> VPS -> IP / rDNS -> editar PTR**.
Sem PTR = `mail.marujo.dev`, Gmail/Outlook rebaixam ou recusam a entrega.

**RESOLVIDO (2026-08-29):** o TXT de SPF `v=spf1 mx -all` foi publicado no
hPanel e ja responde em todos os resolvers publicos consultados
(`@1.1.1.1`, `@8.8.8.8`, `@208.67.222.222`), com TTL 3600.
Confirmado tambem pelo `scripts/healthcheck.sh` (linha 106-107). O resolver
local do sistema ainda pode devolver o `google-site-verification` antigo
por cache — apos o TTL expirar (3600s) isso desaparece. Fica liberado subir
o DMARC para `quarantine` na data planejada (≥ 2026-09-10), se os relatorios
RUA estiverem limpos.

## SPF - variacoes

- Rollout cauteloso: `v=spf1 mx ~all`
- Recomendado (apos confirmar que so este servidor envia): `v=spf1 mx -all`

## DMARC - endurecimento progressivo

1. `v=DMARC1; p=none; rua=mailto:hi@marujo.dev`  (inicio - so monitorar) - **status atual**
2. `v=DMARC1; p=quarantine; rua=mailto:hi@marujo.dev; pct=100`  (apos ~1-2 semanas sem falhas)
3. `v=DMARC1; p=reject; rua=mailto:hi@marujo.dev`  (regime final)

Checkpoint: aplicado em `p=none` em 2026-08-27. Reavaliar os relatorios RUA
recebidos em `hi@marujo.dev` a partir de **2026-09-10** e, se estiverem
limpos (100% alinhado em SPF/DKIM), subir para o passo 2.

## IPv6 / AAAA

O IPv6 da interface responde, mas:
- o PTR do IPv6 tambem aponta para `srv1844440.hstgr.cloud`;
- o Docker (bridge) nao preserva o IP de origem IPv6 dos clientes, o que prejudica
  antispam e fail2ban.

Publicar `AAAA` para `mail.marujo.dev` sem resolver os dois pontos acima causa
piora de entregabilidade. Manter apenas IPv4 ate then. Para habilitar depois:
configurar PTR IPv6 + `ip6tables`/rede Docker IPv6 e so entao adicionar o AAAA.

## MTA-STS / TLS-RPT (protege contra downgrade de TLS entre servidores)

Politica publicada em `mta-sts.marujo.dev` via Caddy (ver
`config/caddy-mail.snippet.Caddyfile` e `config/mta-sts/.well-known/mta-sts.txt`),
`mode: testing` (so gera relatorio TLS-RPT, nao bloqueia entrega ainda).

| Nome | Tipo | Valor | Status |
|------|------|-------|--------|
| `mta-sts.marujo.dev` | A | `76.13.167.76` | OK (ja coberto pelo wildcard `*.marujo.dev`) |
| `_mta-sts.marujo.dev` | TXT | `v=STSv1; id=202608282316` | A publicar |
| `_smtp._tls.marujo.dev` | TXT | `v=TLSRPTv1; rua=mailto:hi@marujo.dev` | A publicar |

Confirmado: `curl https://mta-sts.marujo.dev/.well-known/mta-sts.txt` ja
responde 200 com o conteudo da politica (Caddy + wildcard cuidam disso). Falta
so publicar os dois TXT abaixo para o MTA-STS valer de fato.

Sempre que o conteudo de `mta-sts.txt` mudar, o `id` no TXT de
`_mta-sts.marujo.dev` tem que mudar junto (ex.: novo timestamp
`YYYYMMDDHHMM`), senao os receptores continuam usando a politica em cache.

Depois de confirmar (`curl https://mta-sts.marujo.dev/.well-known/mta-sts.txt`)
e de alguns dias sem erro nos relatorios TLS-RPT, trocar `mode: testing` para
`mode: enforce` no arquivo da politica (e subir o `id`).
