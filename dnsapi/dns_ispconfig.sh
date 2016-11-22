#!/usr/bin/env sh

# ISPConfig 3.1 API
# User must provide login data and URL to the ISPConfig installation incl. port. The remote user in ISPConfig must have access to:
# - DNS zone Functions
# - DNS txt Functions

# Report bugs to https://github.com/sjau/acme.sh

# Values to export:
# export ISPC_User="remoteUser"
# export ISPC_Password="remotePasword"
# export ISPC_Api="https://ispc.domain.tld:8080/remote/json.php"
# export ISPC_Api_Insecure=1     # Set 1 for insecure and 0 for secure -> difference is whether ssl cert is checked for validity (0) or whether it is just accepted (1)

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ispconfig_add() {
  fulldomain="${1}"
  txtvalue="${2}"
  _ISPC_credentials && _ISPC_login && _ISPC_getZoneInfo && _ISPC_addTxt
}

#Usage: dns_myapi_rm   _acme-challenge.www.domain.com
dns_ispconfig_rm() {
  fulldomain="${1}"
  _ISPC_credentials && _ISPC_login && _ISPC_rmTxt
}

####################  Private functions bellow ##################################

_ISPC_credentials() {
  if [ -z "${ISPC_User}" ] || [ -z "$ISPC_Password" ] || [ -z "${ISPC_Api}" ] || [ -z "${ISPC_Api_Insecure}" ]; then
    ISPC_User=""
    ISPC_Password=""
    ISPC_Api=""
    ISPC_Api_Insecure=""
    _err "You haven't specified the ISPConfig Login data, URL and whether you want check the ISPC SSL cert. Please try again."
    return 1
  else
    _saveaccountconf ISPC_User "${ISPC_User}"
    _saveaccountconf ISPC_Password "${ISPC_Password}"
    _saveaccountconf ISPC_Api "${ISPC_Api}"
    _saveaccountconf ISPC_Api_Insecure "${ISPC_Api_Insecure}"
    # Set whether curl should use secure or insecure mode
    HTTPS_INSECURE="${ISPC_Api_Insecure}"
  fi
}

_ISPC_login() {
  _info "Getting Session ID"
  curData="{\"username\":\"${ISPC_User}\",\"password\":\"${ISPC_Password}\",\"client_login\":false}"
  curResult=$(_post "${curData}" "${ISPC_Api}?login")
  if _contains "${curResult}" '"code":"ok"'; then
    sessionID=$(echo "${curResult}" | _egrep_o "response.*" | cut -d ':' -f 2 | cut -d '"' -f 2)
    _info "Successfully retrieved Session ID."
  else
    _err "Couldn't retrieve the Session ID."
    return 1
  fi
}

_ISPC_getZoneInfo() {
  _info "Getting Zoneinfo"
  zoneEnd=false
  curZone="${fulldomain}"
  while [ "${zoneEnd}" = false ]; do
    # we can strip the first part of the fulldomain, since it's just the _acme-challenge string
    curZone="${curZone#*.}"
    # suffix . needed for zone -> domain.tld.
    curData="{\"session_id\":\"${sessionID}\",\"primary_id\":[{\"origin\":\"${curZone}.\"}]}"
    curResult=$(_post "${curData}" "${ISPC_Api}?dns_zone_get")
    if _contains "${curResult}" '"id":"'; then
      zoneFound=true
      zoneEnd=true
      _info "Successfully retrieved zone data."
    fi
    if [ "${curZone#*.}" != "$curZone" ]; then
      _debug2 "$curZone still contains a '.' - so we can check next higher level"
    else
      zoneEnd=true
      _err "Couldn't retrieve zone info."
      return 1
    fi
  done
  if [ "${zoneFound}" ]; then
    server_id=$(echo "${curResult}" | _egrep_o "server_id.*" | cut -d ':' -f 2 | cut -d '"' -f 2)
    case "${server_id}" in
      '' | *[!0-9]*)
        _err "Server ID is not numeric."
        return 1
        ;;
      *) _info "Successfully retrieved Server ID" ;;
    esac
    zone=$(echo "${curResult}" | _egrep_o "\"id.*" | cut -d ':' -f 2 | cut -d '"' -f 2)
    case "${zone}" in
      '' | *[!0-9]*)
        _err "Zone ID is not numeric."
        return 1
        ;;
      *) _info "Successfully retrieved Zone ID" ;;
    esac
    client_id=$(echo "${curResult}" | _egrep_o "sys_userid.*" | cut -d ':' -f 2 | cut -d '"' -f 2)
    case "${client_id}" in
      '' | *[!0-9]*)
        _err "Client ID is not numeric."
        return 1
        ;;
      *) _info "Successfully retrieved Client ID" ;;
    esac
    zoneFound=""
    zoneEnd=""
  fi
}

_ISPC_addTxt() {
  curSerial="$(date +%s)"
  curStamp="$(date +'%F %T')"
  params="\"server_id\":\"${server_id}\",\"zone\":\"${zone}\",\"name\":\"${fulldomain}.\",\"type\":\"txt\",\"data\":\"${txtvalue}\",\"aux\":\"0\",\"ttl\":\"3600\",\"active\":\"y\",\"stamp\":\"${curStamp}\",\"serial\":\"${curSerial}\""
  curData="{\"session_id\":\"${sessionID}\",\"client_id\":\"${client_id}\",\"params\":{${params}}}"
  curResult=$(_post "${curData}" "${ISPC_Api}?dns_txt_add")
  record_id=$(echo "${curResult}" | _egrep_o "\"response.*" | cut -d ':' -f 2 | cut -d '"' -f 2)
  case "${record_id}" in
    '' | *[!0-9]*)
      _err "Record ID is not numeric."
      return 1
      ;;
    *)
      _info "Successfully retrieved Record ID"
      # Make space seperated string of record IDs for later removal.
      record_data="$record_data $record_id"
      ;;
  esac
}

_ISPC_rmTxt() {
  # Need to get the record ID.
  curData="{\"session_id\":\"${sessionID}\",\"primary_id\":[{\"name\":\"${fulldomain}.\"}]}"
  curResult=$(_post "${curData}" "${ISPC_Api}?dns_txt_get")
  # The array search doesn't work properly... so we loop through all retrieved records and check if it contains $fulldomain
  IFS='{'
  for i in ${curResult}; do
    if _contains "${i}" "${fulldomain}"; then
      _info "Successfully found ACME challenge txt record."
      record_id=$(echo "${i}" | _egrep_o "\"id.*" | cut -d ':' -f 2 | cut -d '"' -f 2)
      case "${record_id}" in
        '' | *[!0-9]*)
          # Setting to debug only becase there's no harm if the txt record remains
          _debug "Record ID is not numeric."
          return 1
          ;;
        *) _info "Successfully retrieved Record ID" ;;
      esac
    fi
  done
  # Check if a record id was found
  if [ -z "${record_id}" ]; then
    _debug "No Record ID found for '${fulldomain}'"
    return 1
  fi
  # Delete the record 
  curData="{\"session_id\":\"${sessionID}\",\"primary_id\":\"${record_id}\"}"
  echo $curData; 
  curResult=$(_post "${curData}" "${ISPC_Api}?dns_txt_delete")
  echo $curResult; exit;
  if _contains "${curResult}" '"code":"ok"'; then
    _info "Successfully removed ACME challenge txt record."
  else
    # Setting it to debug only because there's no harm if the txt record remains
    _debug "Couldn't remove ACME challenge txt record."
    return 1
  fi
}
