#!/bin/bash

[[ "${ETH2_CLIENT}" == "teku" ]] && CERT_REQUEST="-k --cert-type P12 --cert /security/teku/cert/teku_client_keystore.p12:dappnode"

# Log level function: $1 = logType $2 = message
function log {
  case $1 in
  debug)
    [[ $LOG_LEVEL -le 0 ]] && echo "[ DEBUG-cron ] ${2}"
    ;;
  info)
    [[ $LOG_LEVEL -le 1 ]] && echo "[ INFO-cron ] ${2}"
    ;;
  warn)
    [[ $LOG_LEVEL -le 2 ]] && echo "[ WARN-cron ] ${2}"
    ;;
  error)
    [[ $LOG_LEVEL -le 3 ]] && echo "[ ERROR-cron ] ${2}"
    ;;
  esac
}

# API responses middleware: $1=http_code $2=content $3=api
function response_middleware() {
  local http_code=$1 content=$2 api=$3
  case ${http_code} in
  200)
    log debug "success response from ${api}: ${content}, HTTP code ${http_code}"
    ;;
  *)
    {
      log error "error response from ${api}: ${content}, HTTP code ${http_code}"
      exit 0
    }
    ;;
  esac
}

##################
# WEB3SIGNER API #
##################

# Get the web3signer status into the variable WEB3SIGNER_STATUS
# https://consensys.github.io/web3signer/web3signer-eth2.html#tag/Server-Status
# Response: plain text
function get_web3signer_status() {
  local response content http_code
  response=$(curl -s -w "%{http_code}" -X GET -H "Content-Type: application/json" -H "Host: web3signer.web3signer-prater.dappnode" "${WEB3SIGNER_API}/upcheck")
  http_code=${response: -3}
  content=$(echo "${response}" | head -c-4)
  response_middleware "$http_code" "$content" "web3signer"
  WEB3SIGNER_STATUS=$content
}

# Get public keys from web3signer API into the variable WEB3SIGNER_PUBLIC_KEYS
# https://consensys.github.io/web3signer/web3signer-eth2.html#operation/KEYMANAGER_LIST
# Response:
# {
#   "data": [
#       {
#           "validating_pubkey": "0x93247f2209abcacf57b75a51dafae777f9dd38bc7053d1af526f220a7489a6d3a2753e5f3e8b1cfe39b56f43611df74a",
#           "derivation_path": "m/12381/3600/0/0/0",
#           "readonly": true
#       }
#   ]
# }
function get_web3signer_pubkeys() {
  local response content http_code
  response=$(curl -s -w "%{http_code}" -X GET -H "Content-Type: application/json" -H "Host: web3signer.web3signer-prater.dappnode" "${WEB3SIGNER_API}/eth/v1/keystores")
  http_code=${response: -3}
  content=$(echo "${response}" | head -c-4)
  response_middleware "$http_code" "$content" "web3signer"
  WEB3SIGNER_PUBKEYS=($(echo "${content}" | jq -r 'try .data[].validating_pubkey'))
}

##############
# CLIENT API #
##############

# Get beacon node syncing status into the variable IS_BEACON_SYNCING
# https://ethereum.github.io/beacon-APIs/#/Node/getSyncingStatus
# Response format
# {
#   "data": {
#     "head_slot": "1",
#     "sync_distance": "1",
#     "is_syncing": true
#   }
# }
function get_beacon_status() {
  local response http_code content
  response=$(curl -s -w "%{http_code}" -H "Content-Type: application/json" "${BEACON_NODE_API}/eth/v1/node/syncing")
  http_code=${response: -3}
  content=$(echo "${response}" | head -c-4)
  client_response_middleware "$http_code" "$content"
  IS_BEACON_SYNCING=$(echo "${content}" | jq -r 'try .data.is_syncing')
}

# Get public keys from client keymanager API into the variable CLIENT_PUBKEYS
# https://ethereum.github.io/keymanager-APIs/#/Remote%20Key%20Manager/ListRemoteKeys
# Response:
# {
#   "data": [
#     {
#       "pubkey": "0x93247f2209abcacf57b75a51dafae777f9dd38bc7053d1af526f220a7489a6d3a2753e5f3e8b1cfe39b56f43611df74a",
#       "url": "https://remote.signer",
#       "readonly": true
#     }
#   ]
# }
function get_client_pubkeys() {
  local response content http_code
  response=$(curl -s -w "%{http_code}" "${CERT_REQUEST}" -X GET -H "Authorization: Bearer ${AUTH_TOKEN}" -H "Content-Type: application/json" "${CLIENT_API}/eth/v1/remotekeys")
  http_code=${response: -3}
  content=$(echo "${response}" | head -c-4)
  response_middleware "$http_code" "$content" "$ETH2_CLIENT"
  CLIENT_PUBKEYS=($(echo "${content}" | jq -r 'try .data[].pubkey'))
}

# Import public keys in client keymanager API
# https://ethereum.github.io/keymanager-APIs/#/Remote%20Key%20Manager/ImportRemoteKeys
# Request format
# {
#   "remote_keys": [
#     {
#       "pubkey": "0x93247f2209abcacf57b75a51dafae777f9dd38bc7053d1af526f220a7489a6d3a2753e5f3e8b1cfe39b56f43611df74a",
#       "url": "https://remote.signer"
#     }
#   ]
# }
function post_client_pubkey() {
  local request response http_code content
  request='{"remote_keys": [{"pubkey": "'${1}'", "url": "'${WEB3SIGNER_API}'"}]}'
  response=$(curl -s -w "%{http_code}" "${CERT_REQUEST}" -X POST -H "Authorization: Bearer ${AUTH_TOKEN}" -H "Content-Type: application/json" --data "${request}" "${CLIENT_API}/eth/v1/remotekeys")
  http_code=${response: -3}
  content=$(echo "${response}" | head -c-4)
  response_middleware "$http_code" "$content" "$ETH2_CLIENT"
}

# Delete public keys from client keymanager API
# https://ethereum.github.io/keymanager-APIs/#/Remote%20Key%20Manager/DeleteRemoteKeys
# Request format
# {
#   "pubkeys": [
#     "0x93247f2209abcacf57b75a51dafae777f9dd38bc7053d1af526f220a7489a6d3a2753e5f3e8b1cfe39b56f43611df74a"
#   ]
# }
function delete_client_pubkey() {
  local request response http_code content
  request='{"pubkeys": ["'${1}'"]}'
  response=$(curl -s -w "%{http_code}" "${CERT_REQUEST}" -X DELETE -H "Authorization: Bearer ${AUTH_TOKEN}" -H "Content-Type: application/json" --data "${request}" "${CLIENT_API}/eth/v1/remotekeys")
  http_code=${response: -3}
  content=$(echo "${response}" | head -c-4)
  response_middleware "$http_code" "$content" "$ETH2_CLIENT"
}

#########
# UTILS #
#########

# Compares the public keys from the web3signer with the public keys from the validator client
function compare_public_keys() {
  log debug "client public keys: ${#CLIENT_PUBKEYS[@]}"
  log debug "web3signer public keys: ${#WEB3SIGNER_PUBKEYS[@]}"

  # Delete pubkeys if necessary
  local pubkeys_to_delete
  for pubkey in "${CLIENT_PUBKEYS[@]}"; do
    [[ ! " ${WEB3SIGNER_PUBKEYS[*]} " =~ ${pubkey} ]] && pubkeys_to_delete+=("${pubkey}")
  done
  if [[ ${#pubkeys_to_delete[@]} -ne 0 ]]; then
    for pubkey in "${pubkeys_to_delete[@]}"; do
      log info "deleting pubkey ${pubkey}"
      delete_client_pubkey "${pubkey}"
    done
  else
    log debug "no pubkeys to delete"
  fi

  # Import pubkeys if necessary
  local pubkeys_to_import
  for pubkey in "${WEB3SIGNER_PUBKEYS[@]}"; do
    [[ ! " ${CLIENT_PUBKEYS[*]} " =~ ${pubkey} ]] && pubkeys_to_import+=("${pubkey}")
  done
  if [[ ${#pubkeys_to_import[@]} -ne 0 ]]; then
    for pubkey in "${pubkeys_to_import[@]}"; do
      log info "importing pubkey ${pubkey}"
      post_client_pubkey "${pubkey}"
    done
  else
    log debug "no pubkeys to import"
  fi
}

function read_token_file() {
  if [[ -f ${TOKEN_FILE} ]]; then
    AUTH_TOKEN=$(cat "${TOKEN_FILE}")
    if [[ -z ${AUTH_TOKEN} ]]; then
      log error "token file is empty"
      exit 1
    fi
  else
    log error "token file not found in ${TOKEN_FILE}"
    exit 1
  fi
}

########
# MAIN #
########

log debug "starting cronjob"

get_beacon_status # IS_BEACON_SYNCING
log debug "beacon node syncing status: ${IS_BEACON_SYNCING}"
if [[ "${IS_BEACON_SYNCING}" == "true" ]]; then
  log info "beacon node is syncing, ${ETH2_CLIENT} API is not available, skipping public key comparison"
  exit 0
fi

get_web3signer_status # WEB3SIGNER_STATUS
log debug "web3signer status: ${WEB3SIGNER_STATUS}"
if [[ "${WEB3SIGNER_STATUS}" != "OK" ]]; then
  log info "web3signer is not available, skipping public key comparison"
  exit 0
fi

get_web3signer_pubkeys # WEBWEB3SIGNER_PUBKEYS
log debug "web3signer public keys: ${WEB3SIGNER_PUBKEYS[*]}"

read_token_file # AUTH_TOKEN
log debug "token: ${AUTH_TOKEN}"

get_client_pubkeys # CLIENT_PUBKEYS
log debug "client public keys: ${CLIENT_PUBKEYS[*]}"

log debug "comparing public keys"
compare_public_keys

log debug "finished cronjob"
exit 0