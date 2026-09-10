#! /usr/bin/env /bin/sh

## self-contained: no need to source provisioning/.envrc first. ENDPOINT/USERNAME/INSECURE
## default below (override by exporting them yourself first, e.g. via provisioning/.envrc);
## PASSWORD, if not already set, is decrypted from secrets/msaxena.yaml.
## end-goal: automatically set PROXMOX_VE_AUTH_TICKET and PROXMOX_VE_CSRF_PREVENTION_TOKEN
##
## every optional input is dereferenced with ":-". The justfile's plan/apply recipes source
## this under `set -u`, where a bare ${PROXMOX_VE_PASSWORD} or $1 is a fatal "unbound
## variable" rather than the empty string these tests expect.

repo_root=$(git rev-parse --show-toplevel)

: "${PROXMOX_VE_ENDPOINT:=https://10.0.10.3:8006/}"
: "${PROXMOX_VE_USERNAME:=root@pam}"
: "${PROXMOX_VE_INSECURE:=true}"
export PROXMOX_VE_ENDPOINT PROXMOX_VE_USERNAME PROXMOX_VE_INSECURE

_password_derived=0
if [ -z "${PROXMOX_VE_PASSWORD:-}" ]; then
  PROXMOX_VE_PASSWORD=$(sops -d --extract '["proxmox"]["root_pam-password"]' "${repo_root}/secrets/msaxena.yaml")
  _password_derived=1
  if [ -z "${PROXMOX_VE_PASSWORD:-}" ]; then
    echo "ERROR: could not decrypt proxmox/root_pam-password from secrets/msaxena.yaml." >&2
    echo "See CLAUDE.md's 'Authenticating to the Proxmox API' section, or export PROXMOX_VE_PASSWORD yourself." >&2
    return 1
  fi
fi

_user_totp_password=${1:-} ## optional: pass a live code to skip the sops/oathtool lookup below

proxmox_api_ticket_path='api2/json/access/ticket' ## cannot have double "//" - ensure endpoint ends with a "/" and this string does not begin with a "/", or vice-versa

## Derive a live TOTP code from the seed in secrets/msaxena.yaml, rather than asking a human
## to read one off a phone. A function, not a one-off, because a redeemed code cannot be
## reused: if PVE rejects one as already-seen we wait out the window and call this again.
_derive_totp() {
  totp_secret=$(sops -d --extract '["proxmox"]["root_pam-totp-secret"]' "${repo_root}/secrets/msaxena.yaml")
  if [ -z "${totp_secret}" ]; then
    echo "ERROR: could not decrypt proxmox/root_pam-totp-secret from secrets/msaxena.yaml." >&2
    echo "See CLAUDE.md's 'Authenticating to the Proxmox API' section, or pass a live code as \$1." >&2
    return 1
  fi
  ## oathtool comes from the flake's devShell (direnv); fall back to an ad-hoc,
  ## unpinned copy only when the shell isn't loaded.
  if command -v oathtool >/dev/null 2>&1; then
    oathtool --totp -b "${totp_secret}"
  else
    nix shell nixpkgs#oath-toolkit --command oathtool --totp -b "${totp_secret}"
  fi
}

## One complete password -> (optional) TOTP exchange, setting auth_ticket and resp_csrf.
_pve_ticket_exchange() {
  resp=$( curl -q -s -k --data-urlencode "username=${PROXMOX_VE_USERNAME}"  --data-urlencode "password=${PROXMOX_VE_PASSWORD}"  "${PROXMOX_VE_ENDPOINT}${proxmox_api_ticket_path}" )
  auth_ticket=$( jq -r '.data.ticket' <<<"${resp}" )
  resp_csrf=$( jq -r '.data.CSRFPreventionToken' <<<"${resp}" )

  ## no second factor demanded: the stage-one ticket is already the real one
  [[ $(jq -r '.data.NeedTFA' <<<"${resp}") == 1 ]] || return 0

  if [ -z "${_user_totp_password}" ]; then
    _user_totp_password=$(_derive_totp) || return 1
    _totp_derived=1
  fi

  resp=$( curl -q -s -k  -H "CSRFPreventionToken: ${resp_csrf}" --data-urlencode  "username=${PROXMOX_VE_USERNAME}" --data-urlencode "tfa-challenge=${auth_ticket}" --data-urlencode "password=totp:${_user_totp_password}"  "${PROXMOX_VE_ENDPOINT}${proxmox_api_ticket_path}" )
  auth_ticket=$( jq -r '.data.ticket' <<<"${resp}" )
  resp_csrf=$( jq -r '.data.CSRFPreventionToken' <<<"${resp}" )
}

## A PVE ticket is valid for two hours, so a run that needs several tofu or API calls should
## not redeem a TOTP code for each one. Cache it, keyed on the endpoint and username, and
## reuse it while it is comfortably inside that window.
##
## The cache holds a bearer credential, so it lives outside the repo, in the user's cache
## directory at mode 0600 -- the same exposure as an ssh-agent socket, and for the same
## reason: the alternative is re-authenticating constantly. Set PVE_AUTH_REFRESH=1 to ignore
## it, and deleting the file is always safe.
_pve_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/nix-homelab"
_pve_cache="${_pve_cache_dir}/pve-ticket-$(printf '%s' "${PROXMOX_VE_ENDPOINT}${PROXMOX_VE_USERNAME}" | shasum -a 256 | cut -c1-16)"
_pve_max_age=6000 ## 100 minutes, inside PVE's two hours with room for a long apply

_pve_cache_load() {
  [ "${PVE_AUTH_REFRESH:-0}" = "1" ] && return 1
  [ -r "${_pve_cache}" ] || return 1
  ## shellcheck disable=SC1090
  . "${_pve_cache}"
  [ -n "${_cached_ticket:-}" ] || return 1
  age=$(( $(date +%s) - ${_cached_at:-0} ))
  [ "$age" -lt "$_pve_max_age" ] || return 1
  ## Age is necessary but not sufficient: a ticket is also void if the node rebooted or the
  ## account changed. Prove it works rather than trusting the clock.
  code=$(curl -q -s -k -o /dev/null -w '%{http_code}' \
    -H "Cookie: PVEAuthCookie=${_cached_ticket}" \
    "${PROXMOX_VE_ENDPOINT}api2/json/version")
  [ "$code" = "200" ] || return 1
  auth_ticket="${_cached_ticket}"
  resp_csrf="${_cached_csrf:-}"
  return 0
}

_pve_cache_store() {
  mkdir -p "${_pve_cache_dir}" 2>/dev/null || return 0
  umask 077
  {
    printf '_cached_at=%s\n' "$(date +%s)"
    printf '_cached_ticket=%s\n' "${auth_ticket}"
    printf '_cached_csrf=%s\n' "${resp_csrf}"
  } > "${_pve_cache}"
  chmod 600 "${_pve_cache}" 2>/dev/null || true
}

_totp_derived=0
if _pve_cache_load; then
  : ## reusing a cached ticket; no TOTP code is redeemed
else
  _pve_ticket_exchange || return 1
fi

## PVE refuses a TOTP code it has already redeemed, and answers with a null ticket instead of
## an error. So two commands inside the same 30-second window (`just packer-token` then
## `just apply`, say) leave the ticket as the literal string "null", and the failure only
## surfaces later as tofu's misleading "failed to create API client: AuthTicket must include
## a valid username". When the code came from the seed we can just wait out the window and
## redeem a fresh one; a code passed by hand as $1 cannot be regenerated, so don't retry it.
if [ "${auth_ticket}" = "null" ] || [ -z "${auth_ticket}" ]; then
  if [ "${_totp_derived}" = 1 ]; then
    _wait=$(( 31 - $(date +%s) % 30 ))
    echo "PVE rejected the TOTP code as already used. Waiting ${_wait}s for the next window." >&2
    sleep "${_wait}"
    _user_totp_password=""
    _pve_ticket_exchange || return 1
  fi
fi

## Never export a non-ticket. Without this the failure is silent here and reappears much
## later, as a provider error from whichever tofu command happens to run next.
if [ "${auth_ticket}" = "null" ] || [ -z "${auth_ticket}" ]; then
  echo "ERROR: Proxmox returned no auth ticket. Its response was:" >&2
  jq -r '.errors // .message // .' <<<"${resp}" >&2
  return 1
fi

_pve_cache_store

export PROXMOX_VE_AUTH_TICKET="${auth_ticket}"
export PROXMOX_VE_CSRF_PREVENTION_TOKEN="${resp_csrf}"

unset -f _derive_totp _pve_ticket_exchange _pve_cache_load _pve_cache_store

## the ticket is what tofu actually authenticates with from here; don't leave a derived
## plaintext password sitting in the shell any longer than the exchange above needed it for.
if [ "${_password_derived}" = 1 ]; then
  unset PROXMOX_VE_PASSWORD
fi
