<?php

/**
 * SimpleSAMLphp 2.x configuration for the lightweight SAML IdP container.
 * All secrets are read from environment variables; the entrypoint.sh ensures
 * they are always set before Apache starts.
 */

$config = [

    // -------------------------------------------------------------------------
    // Basic settings
    // -------------------------------------------------------------------------
    'baseurlpath'       => 'simplesaml/',
    'certdir'           => '/var/simplesamlphp/cert/',
    'loggingdir'        => '/var/simplesamlphp/log/',
    'datadir'           => '/var/simplesamlphp/data/',
    'tempdir'           => '/tmp/simplesaml',

    'technicalcontact_name'  => 'Administrator',
    'technicalcontact_email' => 'na@example.com',

    'timezone' => 'UTC',

    // -------------------------------------------------------------------------
    // Security secrets — always set by entrypoint.sh from env vars
    // -------------------------------------------------------------------------
    'secretsalt'        => (string) getenv('SECRET_SALT'),
    'auth.adminpassword' => (string) getenv('ADMIN_PASSWORD'),

    // -------------------------------------------------------------------------
    // URL trust — allow any host (needed for dynamic App Runner URLs)
    // -------------------------------------------------------------------------
    'trusted.url.regex' => true,

    // -------------------------------------------------------------------------
    // Enable SAML 2.0 IdP
    // -------------------------------------------------------------------------
    'enable.saml20-idp' => true,

    // -------------------------------------------------------------------------
    // Session / store
    // -------------------------------------------------------------------------
    'store.type' => 'phpsession',

    // Secure + SameSite=None required for cross-site SAML redirects from Cognito
    'session.cookie.secure'   => true,
    'session.cookie.samesite' => 'None',
    'session.cookie.httponly' => true,

    // -------------------------------------------------------------------------
    // Logging — errorlog sends to PHP error_log → Apache stderr → CloudWatch
    // -------------------------------------------------------------------------
    'logging.level'   => \SimpleSAML\Logger::NOTICE,
    'logging.handler' => 'errorlog',

    // -------------------------------------------------------------------------
    // Module enable list
    // -------------------------------------------------------------------------
    'module.enable' => [
        'exampleauth' => true,
        'core'        => true,
        'saml'        => true,
        'admin'       => true,
    ],

    // -------------------------------------------------------------------------
    // Language
    // -------------------------------------------------------------------------
    'language.default' => 'en',
];
