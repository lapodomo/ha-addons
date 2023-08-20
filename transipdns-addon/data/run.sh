#!/usr/bin/with-contenv bashio

#bashio::log.level "debug"

source transIP_dns.sh


CERT_DIR=/data/letsencrypt
WORK_DIR=/data/workdir

# Let's encrypt
LE_UPDATE="0"
DOMAIN=$(bashio::config 'domain')
WAIT_TIME=$(bashio::config 'seconds')


# Function that performe a renew
function le_renew() {
    local domain_args=()
    local aliases=''

    # Prepare domain for Let's Encrypt
        for alias in $(jq --raw-output --exit-status "[.aliases[]|{(.alias):.domain}]|add.\"${DOMAIN}\" | select(. != null)" /data/options.json) ; do
            aliases="${aliases} ${alias}"
        done
    

    aliases="$(echo "${aliases}" | tr ' ' '\n' | sort | uniq)"

    bashio::log.info "Renew certificate for domains: $(echo -n "${DOMAIN}") and aliases: $(echo -n "${aliases}")"

 
    domain_args+=("--domain" "${DOMAIN}")
 

    dehydrated --cron --hook ./hooks.sh --challenge dns-01 "${domain_args[@]}" --out "${CERT_DIR}" --config "${WORK_DIR}/config" || true
    LE_UPDATE="$(date +%s)"
}   

# Register/generate certificate if terms accepted
if bashio::config.true 'lets_encrypt.accept_terms'; then
    # Init folder structs
    mkdir -p "${CERT_DIR}"
    mkdir -p "${WORK_DIR}"

    # Clean up possible stale lock file
    if [ -e "${WORK_DIR}/lock" ]; then
        rm -f "${WORK_DIR}/lock"
        bashio::log.warning "Reset dehydrated lock file"
    fi

    # Generate new certs
    if [ ! -d "${CERT_DIR}/live" ]; then
        # Create empty dehydrated config file so that this dir will be used for storage
        touch "${WORK_DIR}/config"

        dehydrated --register --accept-terms --config "${WORK_DIR}/config"
    fi
fi

while true; do


    #if ! _checkDnsARecord "$DOMAIN" ; then
        _checkDnsARecord "$DOMAIN"
        now="$(date +%s)"
        if bashio::config.true 'lets_encrypt.accept_terms' && [ $((now - LE_UPDATE)) -ge 43200 ]; then
            le_renew
        fi
    #fi
    
    sleep "${WAIT_TIME}"
done
