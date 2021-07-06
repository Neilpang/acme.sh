#!/usr/bin/env sh

# HUAWEICLOUD_Username
# HUAWEICLOUD_Password
# HUAWEICLOUD_ProjectID
# HUAWEICLOUD_AuthType=main/sub

iam_api="https://iam.myhuaweicloud.com"
dns_api="https://dns.ap-southeast-1.myhuaweicloud.com" # Should work

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
#
# Ref: https://support.huaweicloud.com/intl/zh-cn/api-dns/zh-cn_topic_0132421999.html
#

dns_huaweicloud_add() {
  fulldomain=$1
  txtvalue=$2

  HUAWEICLOUD_Username="${HUAWEICLOUD_Username:-$(_readaccountconf_mutable HUAWEICLOUD_Username)}"
  HUAWEICLOUD_Password="${HUAWEICLOUD_Password:-$(_readaccountconf_mutable HUAWEICLOUD_Password)}"
  HUAWEICLOUD_ProjectID="${HUAWEICLOUD_ProjectID:-$(_readaccountconf_mutable HUAWEICLOUD_ProjectID)}"
  HUAWEICLOUD_AuthType="${HUAWEICLOUD_AuthType:-$(_readaccountconf_mutable HUAWEICLOUD_AuthType)}"

  # Check information
  if [ -z "${HUAWEICLOUD_Username}" ] || [ -z "${HUAWEICLOUD_Password}" ] || [ -z "${HUAWEICLOUD_ProjectID}" ]; then
    _err "Not enough information provided to dns_huaweicloud!"
    return 1
  fi

  # Check Auth Type
  if [ -z "${HUAWEICLOUD_AuthType}" ]; then
    HUAWEICLOUD_AuthType="main"
  fi

  unset token # Clear token
  token="$(_get_token "${HUAWEICLOUD_Username}" "${HUAWEICLOUD_Password}" "${HUAWEICLOUD_ProjectID}" "${HUAWEICLOUD_AuthType}")"
  if [ -z "${token}" ]; then # Check token
    _err "dns_api(dns_huaweicloud): Error getting token."
    return 1
  fi
  _debug "Access token is: ${token}"

  unset zoneid
  zoneid="$(_get_zoneid "${token}" "${fulldomain}")"
  if [ -z "${zoneid}" ]; then
    _err "dns_api(dns_huaweicloud): Error getting zone id."
    return 1
  fi
  _debug "Zone ID is: ${zoneid}"

  _debug "Adding Record"
  _add_record "${token}" "${fulldomain}" "${txtvalue}"
  ret="$?"
  if [ "${ret}" != "0" ]; then
    _err "dns_api(dns_huaweicloud): Error adding record."
    return 1
  fi

  # Do saving work if all succeeded
  _saveaccountconf_mutable HUAWEICLOUD_Username "${HUAWEICLOUD_Username}"
  _saveaccountconf_mutable HUAWEICLOUD_Password "${HUAWEICLOUD_Password}"
  _saveaccountconf_mutable HUAWEICLOUD_ProjectID "${HUAWEICLOUD_ProjectID}"
  _saveaccountconf_mutable HUAWEICLOUD_AuthType "${HUAWEICLOUD_AuthType}"
  return 0
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
#
# Ref: https://support.huaweicloud.com/intl/zh-cn/api-dns/dns_api_64005.html
#

dns_huaweicloud_rm() {
  fulldomain=$1
  txtvalue=$2

  HUAWEICLOUD_Username="${HUAWEICLOUD_Username:-$(_readaccountconf_mutable HUAWEICLOUD_Username)}"
  HUAWEICLOUD_Password="${HUAWEICLOUD_Password:-$(_readaccountconf_mutable HUAWEICLOUD_Password)}"
  HUAWEICLOUD_ProjectID="${HUAWEICLOUD_ProjectID:-$(_readaccountconf_mutable HUAWEICLOUD_ProjectID)}"
  HUAWEICLOUD_AuthType="${HUAWEICLOUD_AuthType:-$(_readaccountconf_mutable HUAWEICLOUD_AuthType)}"

  # Check information
  if [ -z "${HUAWEICLOUD_Username}" ] || [ -z "${HUAWEICLOUD_Password}" ] || [ -z "${HUAWEICLOUD_ProjectID}" ]; then
    _err "Not enough information provided to dns_huaweicloud!"
    return 1
  fi

  # Check Auth Type
  if [ -z "${HUAWEICLOUD_AuthType}" ]; then
    HUAWEICLOUD_AuthType="main"
  fi

  unset token # Clear token
  token="$(_get_token "${HUAWEICLOUD_Username}" "${HUAWEICLOUD_Password}" "${HUAWEICLOUD_ProjectID}" "${HUAWEICLOUD_AuthType}")"
  if [ -z "${token}" ]; then # Check token
    _err "dns_api(dns_huaweicloud): Error getting token."
    return 1
  fi
  _debug "Access token is: ${token}"

  unset zoneid
  zoneid="$(_get_zoneid "${token}" "${fulldomain}")"
  if [ -z "${zoneid}" ]; then
    _err "dns_api(dns_huaweicloud): Error getting zone id."
    return 1
  fi
  _debug "Zone ID is: ${zoneid}"

  # Remove all records
  # Therotically HuaweiCloud does not allow more than one record set
  # But remove them recurringly to increase robusty
  while [ "${record_id}" != "0" ]; do
    _debug "Removing Record"
    _rm_record "${token}" "${zoneid}" "${record_id}"
    record_id="$(_get_recordset_id "${token}" "${fulldomain}" "${zoneid}")"
  done
  return 0
}

###################  Private functions below ##################################

# _get_zoneid
#
# _token=$1
# _domain_string=$2
#
# printf "%s" "${_zoneid}"
_get_zoneid() {
  _token=$1
  _domain_string=$2
  export _H1="X-Auth-Token: ${_token}"

  i=1
  while true; do
    h=$(printf "%s" "${_domain_string}" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi
    _debug "$h"
    response=$(_get "${dns_api}/v2/zones?name=${h}")

    if _contains "${response}" "id"; then
      _debug "Get Zone ID Success."
      _zoneid=$(echo "${response}" | _egrep_o "\"id\": *\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | tr -d " ")
      printf "%s" "${_zoneid}"
      return 0
    fi

    i=$(_math "$i" + 1)
  done
  return 1
}

_get_recordset_id() {
  _token=$1
  _domain=$2
  _zoneid=$3
  export _H1="X-Auth-Token: ${_token}"

  response=$(_get "${dns_api}/v2/zones/${_zoneid}/recordsets?name=${_domain}")
  if _contains "${response}" "id"; then
    _id="$(echo "${response}" | _egrep_o "\"id\": *\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | tr -d " ")"
    printf "%s" "${_id}"
    return 0
  fi
  printf "%s" "0"
  return 1
}

_add_record() {
  _token=$1
  _domain=$2
  _txtvalue=$3

  # Get Existing Records
  export _H1="X-Auth-Token: ${_token}"
  response=$(_get "${dns_api}/v2/zones/${zoneid}/recordsets?name=${_domain}")

  _debug2 "${response}"
  _exist_record=$(echo "${response}" | _egrep_o '"records":[^]]*' | sed 's/\"records\"\:\[//g')
  _debug "${_exist_record}"

  # Check if record exist
  # Generate body data
  if [ -z "${_exist_record}" ]; then
    _post_body="{
      \"name\": \"${_domain}.\",
      \"description\": \"ACME Challenge\",
      \"type\": \"TXT\",
      \"ttl\": 1,
      \"records\": [
        \"\\\"${_txtvalue}\\\"\"
      ]
    }"
  else
    _post_body="{
      \"name\": \"${_domain}.\",
      \"description\": \"ACME Challenge\",
      \"type\": \"TXT\",
      \"ttl\": 1,
      \"records\": [
        ${_exist_record},
        \"\\\"${_txtvalue}\\\"\"
      ]
    }"
  fi

  _record_id="$(_get_recordset_id "${_token}" "${_domain}" "${zoneid}")"
  _debug "Record Set ID is: ${_record_id}"

  # Remove all records
  while [ "${_record_id}" != "0" ]; do
    _debug "Removing Record"
    _rm_record "${_token}" "${zoneid}" "${_record_id}"
    _record_id="$(_get_recordset_id "${_token}" "${_domain}" "${zoneid}")"
  done

  # Add brand new records with all old and new records
  export _H2="Content-Type: application/json"
  export _H1="X-Auth-Token: ${_token}"

  _debug2 "${_post_body}"
  _post "${_post_body}" "${dns_api}/v2/zones/${zoneid}/recordsets" >/dev/null
  _code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")"
  if [ "$_code" != "202" ]; then
    _err "dns_huaweicloud: http code ${_code}"
    return 1
  fi
  return 0
}

# _rm_record $token $zoneid $recordid
# assume ${dns_api} exist
# no output
# return 0
_rm_record() {
  _token=$1
  _zone_id=$2
  _record_id=$3

  export _H2="Content-Type: application/json"
  export _H1="X-Auth-Token: ${_token}"

  _post "" "${dns_api}/v2/zones/${_zone_id}/recordsets/${_record_id}" false "DELETE" >/dev/null
  return $?
}

_get_token() {
  _username=$1
  _password=$2
  _project=$3
  _auth=$4

  _debug "Getting Token | $_auth"
  if [ "${_auth}" = 'main' ]; then

    body="{
       \"auth\": {
         \"identity\": {
           \"methods\": [
             \"password\"
           ],
           \"password\": {
             \"user\": {
               \"name\": \"${_username}\",
               \"password\": \"${_password}\",
               \"domain\": {
                 \"name\": \"${_username}\"
               }
             }
           }
         },
         \"scope\": {
           \"project\": {
             \"id\": \"${_project}\"
           }
         }
       }
     }"
  else
    _iam_user=$(echo "$_username" | awk -F@ '{print $1}')
    _iam_domain=$(echo "$_username" | awk -F@ '{print $2}')

    body="{
      \"auth\": {
        \"identity\": {
          \"methods\": [
            \"password\"
          ],
          \"password\": {
            \"user\": {
              \"name\": \"${_iam_user}\",
              \"password\": \"${_password}\",
              \"domain\": {
                \"name\": \"${_iam_domain}\"
              }
            }
          }
        },
        \"scope\": {
          \"project\": {
            \"id\": \"${_project}\"
          }
        }
      }
    }"
  fi
  export _H1="Content-Type: application/json;charset=utf8"
  _post "${body}" "${iam_api}/v3/auth/tokens" >/dev/null
  _code=$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\\r\\n")
  _token=$(grep "^X-Subject-Token" "$HTTP_HEADER" | cut -d " " -f 2-)
  _debug2 "${_code}"
  printf "%s" "${_token}"
  return 0
}
