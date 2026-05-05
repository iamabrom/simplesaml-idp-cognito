<?php

/**
 * SAML 2.0 hosted IdP metadata.
 *
 * '__DEFAULT__' as the key makes this entry the default for any hostname,
 * which is required because the App Runner URL is dynamic.
 *
 * Cert files (saml.key / saml.crt) are generated at container start by
 * docker/entrypoint.sh and placed in the certdir configured in config.php.
 */

$metadata['__DEFAULT__'] = [

    'host' => '__DEFAULT__',

    // Signing key/cert — resolved via certdir in config.php
    'privatekey'   => 'saml.key',
    'certificate'  => 'saml.crt',

    // Auth source — must match the key defined in authsources.php.tmpl
    'auth' => 'simplesaml-users',

    // Sign assertions and HTTP-Redirect binding messages with RSA-SHA256
    'sign.assertions'    => true,
    'sign.responses'     => true,
    'redirect.sign'      => true,
    'signature.algorithm' => 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256',

    // NameID format expected by Cognito SAML federation
    'NameIDFormat' => 'urn:oasis:names:tc:SAML:2.0:nameid-format:emailAddress',

    // Authproc filters: map OID attribute names, then derive NameID from email
    'authproc' => [
        10 => [
            'class' => 'core:AttributeMap',
            'oid2name',
        ],
        20 => [
            'class'     => 'saml:AttributeNameID',
            'attribute' => 'email',
            'Format'    => 'urn:oasis:names:tc:SAML:2.0:nameid-format:emailAddress',
        ],
    ],
];
