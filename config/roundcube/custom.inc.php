<?php
/**
 * Overrides do Roundcube para o ambiente marujo.dev.
 * Incluido automaticamente pelo entrypoint da imagem (config/*.php).
 */

// Roundcube fica atras do Caddy, que termina o TLS. Confiar nos headers
// X-Forwarded-* vindos das redes internas do Docker.
$config['proxy_whitelist'] = ['127.0.0.1', '::1', '172.16.0.0/12', '10.0.0.0/8'];

// Verificacao estrita do certificado TLS do Dovecot/Postfix (o hostname
// mail.marujo.dev resolve, via alias de rede Docker, para o container 'mail',
// que apresenta o certificado Let's Encrypt valido).
$ssl = [
    'ssl' => [
        'verify_peer'       => true,
        'verify_peer_name'  => true,
        'allow_self_signed' => false,
    ],
];
$config['imap_conn_options'] = $ssl;
$config['smtp_conn_options'] = $ssl;
$config['managesieve_conn_options'] = $ssl;

// Filtros de servidor (Sieve) via ManageSieve do Dovecot.
$config['managesieve_host']   = 'mail.marujo.dev';
$config['managesieve_port']   = 4190;
$config['managesieve_usetls'] = true;

// Endurecimento.
$config['enable_installer']  = false;
$config['session_lifetime']  = 30;
$config['ip_check']          = true;
$config['referer_check']     = true;
$config['x_frame_options']   = 'sameorigin';
$config['login_rate_limit']  = 3;

// Grava tentativas de login (sucesso/falha) em logs/userlogins.log. Usado pelo
// jail dedicado do Fail2ban no host (ver README - Fail2ban para o webmail),
// ja que o Fail2ban interno do container 'mail' ignora a rede Docker.
// A imagem oficial nao aceita ROUNDCUBEMAIL_LOG_DRIVER como env var (so
// aceita 'stdout' hardcoded na geracao inicial do config.inc.php) - por isso
// o driver e forcado aqui, no ultimo include da cadeia de config.
$config['log_driver'] = 'file';
$config['log_logins'] = true;

// Identidade / UX.
$config['product_name']       = 'marujo.dev webmail';
$config['support_url']        = '';
$config['enable_spellcheck']  = false;
$config['mime_param_folding'] = 1;

// Avatares (plugin gravatar): foto de remetentes e destinatarios via Gravatar.
// Ligado por padrao para todos; cada usuario pode desativar em
// Configuracoes -> Catalogo de enderecos. Requisicao servidor->gravatar.com
// (envia o md5 do e-mail do contato) apenas na primeira exibicao de cada
// endereco; sem correspondencia, nenhuma foto e exibida (d=404).
$config['gravatar_enabled'] = true;
$config['gravatar_https']   = true;
