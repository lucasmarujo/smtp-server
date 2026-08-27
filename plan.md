# Projeto: Mail Server próprio para marujo.dev

Você está conectado diretamente à minha VPS Linux e deve implementar um servidor de e-mail completo e funcional para o domínio `marujo.dev`.

## Objetivo

Quero hospedar meu próprio servidor de e-mail na VPS, sem depender de serviços pagos de SMTP/mailbox.

O primeiro endereço deve ser:

`hi@marujo.dev`

O servidor deve permitir:

* receber e-mails enviados para `hi@marujo.dev`;
* enviar e-mails para Gmail, Outlook, Yahoo etc.;
* acessar a caixa postal via IMAP;
* enviar mensagens autenticadas via SMTP Submission;
* TLS obrigatório para clientes;
* SPF;
* DKIM;
* DMARC;
* antispam;
* persistência dos e-mails;
* backups da configuração e das caixas;
* possibilidade de adicionar novos endereços futuramente.

## Stack desejada

Use:

* Postfix — SMTP;
* Dovecot — IMAP;
* Rspamd — antispam + DKIM signing;
* Let's Encrypt — certificados TLS;
* Docker Compose quando fizer sentido;
* UFW para firewall, preservando as regras existentes;
* volumes persistentes para os dados.

Não instale serviços desnecessários no host se eles puderem funcionar em containers.

## REGRA MAIS IMPORTANTE

ANTES DE ALTERAR QUALQUER COISA:

1. Descubra a distribuição Linux e versão.
2. Descubra o IP público da VPS.
3. Descubra o hostname atual.
4. Verifique se Docker e Docker Compose estão instalados.
5. Verifique todos os containers atualmente rodando.
6. Verifique quais portas estão em uso.
7. Verifique as regras atuais do UFW.
8. Verifique se já existe Caddy, Nginx, Traefik ou outro reverse proxy.
9. Verifique a estrutura existente em `/opt`.
10. Não interrompa nem altere serviços existentes sem necessidade.
11. Não altere o Caddy existente.
12. Não altere aplicações existentes.
13. Não faça `docker system prune`, `docker volume prune` ou operações destrutivas.
14. Não faça reset de firewall.
15. Faça backup dos arquivos que você modificar.

Minha VPS já possui outros projetos rodando. O servidor de e-mail deve ser isolado.

## Estrutura

Crie o projeto em:

`/opt/mail`

Estruture de maneira organizada, por exemplo:

```text
/opt/mail/
├── docker-compose.yml
├── .env
├── config/
├── docker-data/
│   ├── postfix/
│   ├── dovecot/
│   ├── rspamd/
│   └── mail/
├── backups/
└── scripts/
```

Não coloque secrets diretamente no `docker-compose.yml`.

O `.env` deve ter permissões restritas.

## Domínio

Domínio:

`marujo.dev`

Hostname de e-mail:

`mail.marujo.dev`

Mailbox inicial:

`hi@marujo.dev`

## DNS

Primeiro determine quais registros DNS precisam existir.

A configuração esperada é aproximadamente:

```text
mail.marujo.dev       A       IP_DA_VPS
marujo.dev            MX      10 mail.marujo.dev
marujo.dev            TXT     SPF
_dmarc.marujo.dev     TXT     DMARC
selector._domainkey.marujo.dev TXT DKIM
```

Não invente o IP.

Descubra o IP público real da VPS.

Também verifique se existe IPv6 configurado.

Se existir IPv6 funcional, configure corretamente o serviço para IPv6.

Se não existir IPv6 funcional, não publique registros AAAA incorretos.

## Reverse DNS / PTR

Verifique o reverse DNS do IP público.

O ideal é:

```text
IP_DA_VPS → mail.marujo.dev
```

Se você não tiver permissão para alterar o PTR pelo servidor, informe claramente que isso precisa ser configurado no painel/provedor da VPS.

NÃO tente inventar ou alterar PTR por conta própria se isso depender do provedor.

## Postfix

Configure o Postfix como servidor SMTP.

Requisitos:

* receber e-mails para `marujo.dev`;
* não ser open relay;
* aceitar envio autenticado apenas;
* submission na porta 587;
* TLS;
* SASL via Dovecot;
* integração com mailbox virtual;
* DKIM via Rspamd;
* boas práticas de segurança.

O servidor NÃO pode permitir:

```text
anonymous relay
```

Teste explicitamente se o servidor pode ser usado como open relay.

Se houver qualquer possibilidade de open relay, corrija antes de finalizar.

## Dovecot

Configure Dovecot para:

* IMAP;
* IMAPS;
* autenticação;
* armazenamento das mensagens;
* integração com Postfix SASL;
* Maildir ou formato equivalente;
* TLS.

Use:

```text
993 → IMAPS
```

Não exponha serviços desnecessários.

## Rspamd

Configure Rspamd para:

* antispam;
* DKIM signing;
* integração com Postfix;
* verificação de SPF;
* verificação de DKIM;
* verificação de DMARC;
* headers apropriados.

Gere uma chave DKIM segura para:

```text
marujo.dev
```

Use um selector razoável, por exemplo:

```text
mail
```

ou outro nome apropriado.

Depois mostre exatamente qual registro TXT preciso adicionar no DNS.

Não exponha a interface administrativa do Rspamd publicamente sem autenticação.

## TLS

Configure TLS usando Let's Encrypt.

Certificado:

```text
mail.marujo.dev
```

O certificado deve funcionar para:

```text
mail.marujo.dev
```

Configure renovação automática.

Não desative a validação TLS.

Clientes devem conseguir configurar:

```text
IMAP:
host: mail.marujo.dev
port: 993
SSL/TLS

SMTP:
host: mail.marujo.dev
port: 587
STARTTLS
authentication required
```

## Firewall

Antes de modificar o UFW, veja o estado atual.

Adicione somente o necessário.

Portas esperadas:

```text
25/tcp
587/tcp
993/tcp
```

A porta 80/443 provavelmente já está sendo utilizada pelo reverse proxy existente.

Não mexa nelas sem necessidade.

Não remova regras existentes.

## Caddy

Se o Caddy já estiver rodando:

NÃO substitua o Caddy.

NÃO coloque SMTP/IMAP atrás do Caddy.

SMTP e IMAP devem ser acessados diretamente através do hostname:

```text
mail.marujo.dev
```

Se quisermos webmail futuramente, aí sim podemos utilizar Caddy para HTTP/HTTPS.

## Webmail

Por enquanto NÃO é obrigatório instalar webmail.

Priorize:

* SMTP;
* IMAP;
* DKIM;
* SPF;
* DMARC;
* antispam;
* TLS.

Se a arquitetura ficar preparada para adicionar Roundcube posteriormente, melhor.

## Mailbox

Crie inicialmente:

```text
hi@marujo.dev
```

Não coloque a senha diretamente no histórico do shell.

Gere uma senha forte aleatória ou solicite uma senha de maneira segura.

A senha deve ficar somente em local seguro.

Documente como adicionar novos usuários posteriormente.

## Segurança

Implemente:

* TLS;
* autenticação SMTP;
* autenticação IMAP;
* rate limiting quando apropriado;
* proteção contra brute force;
* antispam;
* nenhuma possibilidade de open relay;
* containers sem privilégios desnecessários;
* secrets fora do compose;
* volumes persistentes;
* permissões corretas nos arquivos;
* logs.

Se Fail2ban for necessário e compatível com a arquitetura escolhida, considere utilizá-lo.

## Entregabilidade

Faça o máximo possível para melhorar a reputação do servidor.

Configure corretamente:

```text
HELO/EHLO
hostname
PTR
SPF
DKIM
DMARC
TLS
```

Use um hostname consistente:

```text
mail.marujo.dev
```

Evite configurações que façam o servidor parecer spoofado.

## DMARC

Comece com uma política segura e apropriada para implantação inicial.

Por exemplo:

```text
v=DMARC1; p=none; rua=mailto:hi@marujo.dev
```

Mas avalie a configuração final e explique como posso posteriormente mudar para:

```text
p=quarantine
```

e depois:

```text
p=reject
```

Não configure `reject` imediatamente se isso puder causar problemas de entregabilidade durante a implantação.

## Backup

Crie uma estratégia simples de backup.

Preciso conseguir fazer backup de:

* configuração;
* contas;
* mailbox;
* DKIM keys;
* certificados/configuração necessária.

Crie scripts em:

```text
/opt/mail/scripts/
```

Por exemplo:

```text
backup.sh
restore.sh
healthcheck.sh
```

O backup NÃO deve apagar automaticamente backups antigos sem uma política clara.

## Healthcheck

Crie um script:

```text
/opt/mail/scripts/healthcheck.sh
```

Ele deve verificar:

* containers;
* Postfix;
* Dovecot;
* Rspamd;
* portas;
* certificados;
* DNS relevante quando possível;
* configuração básica;
* status do armazenamento.

O script deve retornar código de erro quando houver problema.

## Testes obrigatórios

Depois da instalação, NÃO simplesmente diga "funcionou".

Execute testes reais.

### 1. Containers

Verifique:

```bash
docker compose ps
```

Todos os serviços necessários devem estar saudáveis.

### 2. Portas

Verifique:

```text
25
587
993
```

### 3. SMTP

Teste conexão SMTP.

### 4. IMAP

Teste autenticação do usuário:

```text
hi@marujo.dev
```

### 5. Open relay

Faça um teste para garantir que um usuário não autenticado NÃO consegue utilizar o servidor como relay.

Esse teste é obrigatório.

### 6. TLS

Verifique o certificado e TLS.

### 7. DKIM

Envie um e-mail de teste para uma conta externa, preferencialmente Gmail.

Verifique se aparece:

```text
DKIM: PASS
SPF: PASS
DMARC: PASS
```

### 8. Recebimento

Envie um e-mail de uma conta externa para:

```text
hi@marujo.dev
```

Confirme que ele chega na mailbox.

### 9. Envio

Envie de:

```text
hi@marujo.dev
```

para uma conta externa.

Confirme entrega e autenticações.

## DNS

Se você tiver alguma forma de consultar DNS publicamente, valide:

```text
A
MX
TXT SPF
TXT DKIM
TXT DMARC
PTR
```

Não assuma que o DNS foi configurado corretamente só porque os arquivos locais estão corretos.

Se você NÃO tiver acesso ao provedor DNS, pare a implantação apenas no ponto necessário e me mostre exatamente quais registros eu preciso criar.

## Importante sobre porta 25

Verifique se a porta 25 de saída está bloqueada pelo provedor da VPS.

Faça um teste seguro.

Se estiver bloqueada, NÃO tente contornar o bloqueio.

Nesse caso, explique que a entrega direta entre servidores não funcionará adequadamente e indique exatamente o que precisa ser liberado pelo provedor.

## Logs

Configure logs suficientes para diagnosticar:

* mensagens rejeitadas;
* autenticação;
* spam;
* problemas de TLS;
* entrega;
* recebimento.

Não deixe logs crescerem indefinidamente.

Verifique também se o Docker está configurado para não consumir todo o disco com logs.

## Não fazer

NÃO:

* apagar containers existentes;
* apagar volumes existentes;
* alterar projetos existentes;
* alterar Caddy sem necessidade;
* trocar firewall inteiro;
* executar comandos destrutivos;
* expor Rspamd publicamente sem proteção;
* criar open relay;
* armazenar senhas em Git;
* colocar secrets hardcoded;
* publicar AAAA se IPv6 não estiver funcionando;
* usar HTTP sem TLS para autenticação;
* utilizar a porta 25 para autenticação de usuários.

## Documentação

Ao finalizar, crie:

```text
/opt/mail/README.md
```

O README deve conter:

1. arquitetura;
2. serviços;
3. comandos para subir/descer;
4. comandos para logs;
5. como adicionar mailbox;
6. como remover mailbox;
7. como alterar senha;
8. como gerar/renovar DKIM;
9. como fazer backup;
10. como restaurar backup;
11. como verificar saúde;
12. configuração de clientes;
13. registros DNS;
14. troubleshooting;
15. como atualizar os containers;
16. riscos/consequências de operar um servidor de e-mail próprio.

## Resultado esperado

No final quero conseguir configurar meu cliente de e-mail assim:

```text
Email:
hi@marujo.dev

IMAP:
mail.marujo.dev
993
SSL/TLS

SMTP:
mail.marujo.dev
587
STARTTLS
Authentication:
hi@marujo.dev
```

E quero conseguir:

```text
Gmail → hi@marujo.dev
```

e:

```text
hi@marujo.dev → Gmail
```

funcionando corretamente.

## Processo de execução

Execute o projeto em etapas:

### Etapa 1

Audite a VPS e apresente o que encontrou.

### Etapa 2

Prepare a estrutura em `/opt/mail`.

### Etapa 3

Configure Docker Compose e serviços.

### Etapa 4

Configure DNS necessário e gere DKIM.

### Etapa 5

Configure TLS.

### Etapa 6

Configure Postfix + Dovecot + Rspamd.

### Etapa 7

Configure firewall sem quebrar serviços existentes.

### Etapa 8

Suba os containers.

### Etapa 9

Execute todos os testes.

### Etapa 10

Corrija automaticamente problemas encontrados.

### Etapa 11

Execute novamente os testes.

### Etapa 12

Crie o README e scripts de manutenção.

## Regra final

Não pare simplesmente porque encontrou um problema.

Sempre que possível:

1. diagnostique;
2. corrija;
3. teste novamente.

Mas se alguma ação exigir credencial externa, alteração no painel do provedor, alteração do DNS ou alteração de PTR que você não possui acesso, pare nesse ponto e me diga exatamente:

* o que falta;
* por que falta;
* onde preciso configurar;
* qual valor devo colocar.

No final, apresente um resumo objetivo contendo:

```text
STATUS
Containers:
SMTP:
IMAP:
TLS:
SPF:
DKIM:
DMARC:
PTR:
Firewall:
Open Relay:
Recebimento:
Envio:

DNS que ainda preciso configurar:

Comandos úteis:

Arquivos principais:
```

Não considere o projeto concluído até que os testes possíveis tenham sido executados.
