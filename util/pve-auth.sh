#! /usr/bin/env /bin/sh

## self-contained: no need to source provisioning/.envrc first. ENDPOINT/USERNAME/INSECURE
## default below (override by exporting them yourself first, e.g. via provisioning/.envrc);
## PASSWORD, if not already set, is decrypted from secrets/msaxena.yaml.
## end-goal: automatically set PROXMOX_VE_AUTH_TICKET and PROXMOX_VE_CSRF_PREVENTION_TOKEN

repo_root=$(git rev-parse --show-toplevel)

: "${PROXMOX_VE_ENDPOINT:=https://10.0.10.3:8006/}"
: "${PROXMOX_VE_USERNAME:=root@pam}"
: "${PROXMOX_VE_INSECURE:=true}"
export PROXMOX_VE_ENDPOINT PROXMOX_VE_USERNAME PROXMOX_VE_INSECURE

_password_derived=0
if [ -z "${PROXMOX_VE_PASSWORD}" ]; then
  PROXMOX_VE_PASSWORD=$(sops -d --extract '["proxmox"]["root_pam-password"]' "${repo_root}/secrets/msaxena.yaml")
  _password_derived=1
  if [ -z "${PROXMOX_VE_PASSWORD}" ]; then
    echo "ERROR: could not decrypt proxmox/root_pam-password from secrets/msaxena.yaml." >&2
    echo "See CLAUDE.md's 'Authenticating to the Proxmox API' section, or export PROXMOX_VE_PASSWORD yourself." >&2
    return 1
  fi
fi

_user_totp_password=$1 ## optional: pass a live code to skip the sops/oathtool lookup below

proxmox_api_ticket_path='api2/json/access/ticket' ## cannot have double "//" - ensure endpoint ends with a "/" and this string does not begin with a "/", or vice-versa

## call the auth api endpoint
resp=$( curl -q -s -k --data-urlencode "username=${PROXMOX_VE_USERNAME}"  --data-urlencode "password=${PROXMOX_VE_PASSWORD}"  "${PROXMOX_VE_ENDPOINT}${proxmox_api_ticket_path}" )
auth_ticket=$( jq -r '.data.ticket' <<<"${resp}" )
resp_csrf=$( jq -r '.data.CSRFPreventionToken' <<<"${resp}" )

## check if the response payload needs a TFA (totp) passed, call the auth-api endpoint again
if [[ $(jq -r '.data.NeedTFA' <<<"${resp}") == 1 ]]; then
  if [ -z "${_user_totp_password}" ]; then
    ## derive the live code from the TOTP seed in secrets/msaxena.yaml instead of asking a
    ## human to type one in from their phone/authenticator app each time.
    totp_secret=$(sops -d --extract '["proxmox"]["root_pam-totp-secret"]' "${repo_root}/secrets/msaxena.yaml")
    if [ -z "${totp_secret}" ]; then
      echo "ERROR: could not decrypt proxmox/root_pam-totp-secret from secrets/msaxena.yaml." >&2
      echo "See CLAUDE.md's 'Authenticating to the Proxmox API' section, or pass a live code as \$1." >&2
      return 1
    fi
    _user_totp_password=$(nix shell nixpkgs#oath-toolkit --command oathtool --totp -b "${totp_secret}")
  fi
  resp=$( curl -q -s -k  -H "CSRFPreventionToken: ${resp_csrf}" --data-urlencode  "username=${PROXMOX_VE_USERNAME}" --data-urlencode "tfa-challenge=${auth_ticket}" --data-urlencode "password=totp:${_user_totp_password}"  "${PROXMOX_VE_ENDPOINT}${proxmox_api_ticket_path}" )
  auth_ticket=$( jq -r '.data.ticket' <<<"${resp}" )
  resp_csrf=$( jq -r '.data.CSRFPreventionToken' <<<"${resp}" )
fi

export PROXMOX_VE_AUTH_TICKET="${auth_ticket}"
export PROXMOX_VE_CSRF_PREVENTION_TOKEN="${resp_csrf}"

## the ticket is what tofu actually authenticates with from here; don't leave a derived
## plaintext password sitting in the shell any longer than the exchange above needed it for.
if [ "${_password_derived}" = 1 ]; then
  unset PROXMOX_VE_PASSWORD
fi
