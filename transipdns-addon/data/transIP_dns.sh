#!/usr/bin/with-contenv bashio
TRANSIP_ENDPOINT="https://api.transip.nl/v6/domains"
IPV="https://text.wtfismyip.com"
IPV4=""
IPV6=""

#function to get current IP's
_checkCurrentIP(){
   responseIP=$(curl -s -X GET "$IPV")
      if [ "$?" != "0" ]; then
        bashio::log.error "Could not get currentIP $?"
        return 1
      fi
      if [ "$responseIP" != "${responseIP#*[0-9].[0-9]}" ]; then
        IPV4="$responseIP"
        bashio::log.info "Current IPV4:" "$IPV4"
      elif [ "$responseIP" != "${responseIP#*:[0-9a-fA-F]}" ]; then
        IPV6="$responseIP"
        bashio::log.info "Current IPV6:" "$IPV6"
      else
        bashio::log.error "Unknown IP $responseIP"
      fi
      return 0
}

#function to check transip dns a record
_checkDnsARecord(){
   fulldomain=$1

   _checkCurrentIP
    bashio::log.info "+ Pulling A/AAAA records from DNS"
    if ! _transIP_rest GET "$fulldomain/dns" "" ; then
      bashio::log.error "Could not load DNS records."
    fi
    if [[ "$response" == null ]]; then
      bashio::log.error "Could not get data from TransIP."
    else
    if [[ "$IPV4" != "" ]]; then
        Arecord=$(echo $response | jq -r '. as $root|$root.dnsEntries[] | select(.type == "A") | .content')
        bashio::log.info "DNS record IPV4:" "$Arecord" 
        if [ "$IPV4" != "$Arecord" ]; then
        bashio::log.info "+ Updating DNS record IPV4..." 
        if ! _transIP_rest PATCH "$fulldomain/dns" '{"dnsEntry": {"name": "@","expire": 3600,"type": "A","content": "'"$IPV4"'"}}'; then
          bashio::log.error "Could not update A record."
        fi
        
        if [[ "$response" == "" ]]; then
          bashio::log.info "DNS record IPV4 succesfull updated!" 
        else
          bashio::log.error "Could not update A record."
        fi
        
        else
        bashio::log.info "DNS record IPV4 is up to date" 
        fi
    fi
    if [[ "$IPV6" != "" ]]; then
        Arecord=$(echo $response | jq -r '. as $root|$root.dnsEntries[] | select(.type == "AAAA") | .content')
        bashio::log.info "DNS record IPV6:" "$Arecord" 
        if [ "$IPV6" != "$Arecord" ]; then
        bashio::log.info "+ Updating DNS record IPV6..." 
        if ! _transIP_rest PATCH "$fulldomain/dns" '{"dnsEntry": {"name": "@","expire": 3600,"type": "AAAA","content": "'"$IPV6"'"}}'; then
        bashio::log.error "Could not update AAAA record."
        fi
        if [[ "$response" == "" ]]; then
          bashio::log.info "DNS record IPV6 succesfull updated!" 
        else
          bashio::log.error "Could not update AAAA record."
        fi
        else
        bashio::log.info "DNS record IPV6 is up to date" 
        fi
    fi
    fi

}

#Usage: add _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_challenge_add() {
  fulldomain=$1
  txtvalue=$2
  if bashio::config.true 'updatedns'; then
    bashio::log.info "Update TXT record."
    if ! _transIP_rest PATCH "$fulldomain/dns" '{"dnsEntry": {"name": "_acme-challenge","expire": 60,"type": "TXT","content": "'"$txtvalue"'"}}'; then
      return 1
    fi
    if [[ "$response" == "" ]]; then
      return 0
    else
      bashio::log.error "Could not add TXT record."
      return 1
    fi
  else
    bashio::log.info "Creating TXT record."
    if ! _transIP_rest POST "$fulldomain/dns" '{"dnsEntry": {"name": "_acme-challenge","expire": 60,"type": "TXT","content": "'"$txtvalue"'"}}'; then
      return 1
    fi
    if [[ "$response" == "[]" ]]; then
      return 0
    else
      bashio::log.error "Could not add TXT record."
      return 1
    fi
  fi
  
  
  
}

#Usage: rm _acme-challenge.www.domain.com "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"

delete_dns_record() {
  if bashio::config.true 'updatedns'; then
    fulldomain=$1
    txtvalue=$2
    bashio::log.info "Removing TXT record from DNS"
    if ! _transIP_rest DELETE "$fulldomain/dns" '{"dnsEntry": {"name": "_acme-challenge","expire": 60,"type": "TXT","content": "'"$txtvalue"'"}}'; then
      return 1
    fi
    if [[ "$response" == "" ]]; then
      return 0
    else
      bashio::log.error "Could not remove TXT record."
      return 1
    fi
  fi  
}




_transIP_rest() {
  m=$1
  ep="$2"
  data="$3"
  bashio::log.debug "$ep"
username=$(bashio::config 'username')
nonce=$(echo $RANDOM | md5sum | head -c 20; echo;)
loginpayload='{"login":"'"$username"'","nonce":"'"$nonce"'","read_only":false,"expiration_time":"30 minutes","label":"","global_key":true}'
signature=$(echo -n "$loginpayload"| openssl dgst -sha512 -sign /ssl/private_transip_key.pem | openssl enc -base64 -A)

  _H1="Signature: ${signature}"
  _H2="Content-Type: application/json"

   bearer=$(curl -s -H "$_H1" -H "$_H2" -X POST "https://api.transip.nl/v6/auth" -d "$loginpayload") 
   bearer=$(echo $bearer | jq -r '.token')
   _H1="Authorization: Bearer $bearer"
   response=$(curl -s -H "$_H1" -H "$_H2" -X $m "$TRANSIP_ENDPOINT/$ep" -d "$data")

  if [ "$?" != "0" ]; then
    bashio::log.error "error $ep $?"
    return 1
  fi
  return 0
}


