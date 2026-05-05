# syntax=docker/dockerfile:1

# =============================================================================
# Stage 1 — builder: install SimpleSAMLphp via Composer
# =============================================================================
FROM composer:2 AS builder

WORKDIR /var/simplesamlphp

# Install SSP 2.5.0 into the current directory (no dev dependencies).
# --ignore-platform-req=ext-bcmath: the alpine composer image lacks bcmath;
# it is installed in the runtime stage so this is safe to skip here.
RUN composer create-project \
        simplesamlphp/simplesamlphp:2.5.0 \
        . \
        --no-dev \
        --no-progress \
        --no-interaction \
        --ignore-platform-req=ext-bcmath

# =============================================================================
# Stage 2 — runtime: PHP 8.3 + Apache
# =============================================================================
FROM php:8.3-apache

# ---------------------------------------------------------------------------
# System dependencies + PHP extensions
# ---------------------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libicu-dev \
        libxml2-dev \
        libzip-dev \
    && docker-php-ext-install intl xml zip bcmath \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Apache configuration
# ---------------------------------------------------------------------------
# Enable required modules
RUN a2enmod rewrite remoteip headers

# Listen on 8080 instead of the default 80
RUN sed -i 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf

# Disable the default site; our conf is added below
RUN a2dissite 000-default.conf || true

# ---------------------------------------------------------------------------
# Copy SimpleSAMLphp from builder
# ---------------------------------------------------------------------------
COPY --from=builder /var/simplesamlphp /var/simplesamlphp

# ---------------------------------------------------------------------------
# Overlay our SSP configuration files
# ---------------------------------------------------------------------------
COPY ssp-config/config.php \
         /var/simplesamlphp/config/config.php
COPY ssp-config/authsources.php.tmpl \
         /var/simplesamlphp/config/authsources.php.tmpl
COPY ssp-config/metadata/saml20-idp-hosted.php \
         /var/simplesamlphp/metadata/saml20-idp-hosted.php
COPY ssp-config/metadata/saml20-sp-remote.php.tmpl \
         /var/simplesamlphp/metadata/saml20-sp-remote.php.tmpl

# ---------------------------------------------------------------------------
# Apache virtual host
# ---------------------------------------------------------------------------
COPY docker/apache/simplesamlphp.conf \
         /etc/apache2/sites-available/simplesamlphp.conf
RUN a2ensite simplesamlphp.conf

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
