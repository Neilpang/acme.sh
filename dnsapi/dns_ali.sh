#!/usr/local/bin/bash

Ali_API="https://alidns.aliyuncs.com/"

#ALICLOUD_ACCESS_KEY="LTqIA87hOKdjevsf5"
#ALICLOUD_SECRET_KEY="0p5EYueFNq501xnCPzKNbx6K51qPH2"

#Usage: dns_ali_add   $(_ali_urlencode "_acme-challenge.www.domain.com") "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ali_add() {
  fulldomain=$1
  txtvalue=$2

  ALICLOUD_ACCESS_KEY="${ALICLOUD_ACCESS_KEY:-$(_readaccountconf_mutable ALICLOUD_ACCESS_KEY)}"
  ALICLOUD_SECRET_KEY="${ALICLOUD_SECRET_KEY:-$(_readaccountconf_mutable ALICLOUD_SECRET_KEY)}"

  if [ -z "$ALICLOUD_ACCESS_KEY" ] || [ -z "$ALICLOUD_SECRET_KEY" ]; then
    _use_instance_role
  fi

  if [ -z "$ALICLOUD_ACCESS_KEY" ] || [ -z "$ALICLOUD_SECRET_KEY" ]; then
    ALICLOUD_ACCESS_KEY=""
    ALICLOUD_SECRET_KEY=""
    _err "You don't specify aliyun api key and secret yet."
    return 1
  fi

  #save the api key and secret to the account conf file.
  if [ -z "$_using_role" ]; then
    _saveaccountconf_mutable ALICLOUD_ACCESS_KEY "$ALICLOUD_ACCESS_KEY"
    _saveaccountconf_mutable ALICLOUD_SECRET_KEY "$ALICLOUD_SECRET_KEY"
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    return 1
  fi

  _debug "Add record"
  _add_record_query "$_domain" "$_sub_domain" "$txtvalue" && _ali_rest "Add record"
}

dns_ali_rm() {
  fulldomain=$1
  txtvalue=$2
  ALICLOUD_ACCESS_KEY="${ALICLOUD_ACCESS_KEY:-$(_readaccountconf_mutable ALICLOUD_ACCESS_KEY)}"
  ALICLOUD_SECRET_KEY="${ALICLOUD_SECRET_KEY:-$(_readaccountconf_mutable ALICLOUD_SECRET_KEY)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    return 1
  fi

  _clean
}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _describe_records_query "$h"
    if ! _ali_rest "Get root" "ignore"; then
      return 1
    fi

    if _contains "$response" "PageNumber"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _debug _sub_domain "$_sub_domain"
      _domain="$h"
      _debug _domain "$_domain"
      return 0
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

_use_instance_role() {
  _url="http://100.100.100.200/latest/meta-data/ram/security-credentials/"
  _debug "_url" "$_url"
  if ! _get "$_url" true 1 | _head_n 1 | grep -Fq 200; then
    _debug "Unable to fetch IAM role from instance metadata"
    return 1
  fi
  _ali_instance_role=$(_get "$_url" "" 1)
  _debug "_ali_instance_role" "_ali_instance_role"

  _ali_creds="$(
    _get "$_url$_ali_instance_role" "" 1 |
      _normalizeJson |
      tr '{,}' '\n' |
      while read -r _line; do
        _key="$(echo "${_line%%:*}" | tr -d '"')"
        _value="${_line#*:}"
        _debug3 "_key" "$_key"
        _secure_debug3 "_value" "$_value"
        case "$_key" in
        AccessKeyId) echo "ALICLOUD_ACCESS_KEY=$_value" ;;
        AccessKeySecret) echo "ALICLOUD_SECRET_KEY=$_value" ;;
        SecurityToken) echo "ALICLOUD_SECURITY_TOKEN=$_value" ;;
        esac
      done |
      paste -sd' ' -
  )"
  _secure_debug "_ali_creds" "$_ali_creds"

  if [ -z "$_ali_creds" ]; then
    return 1
  fi

  eval "$_ali_creds"
  _using_role=true
}

_ali_rest() {
  signature=$(printf "%s" "GET&%2F&$(_ali_urlencode "$query")" | _hmac "sha1" "$(printf "%s" "$ALICLOUD_SECRET_KEY&" | _hex_dump | tr -d " ")" | _base64)
  signature=$(_ali_urlencode "$signature")
  url="$Ali_API?$query&Signature=$signature"

  if ! response="$(_get "$url")"; then
    _err "Error <$1>"
    return 1
  fi

  _debug2 response "$response"
  if [ -z "$2" ]; then
    message="$(echo "$response" | _egrep_o "\"Message\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")"
    if [ "$message" ]; then
      _err "$message"
      return 1
    fi
  fi
}

_ali_urlencode() {
  _str="$1"
  _str_len=${#_str}
  _u_i=1
  while [ "$_u_i" -le "$_str_len" ]; do
    _str_c="$(printf "%s" "$_str" | cut -c "$_u_i")"
    case $_str_c in [a-zA-Z0-9.~_-])
      printf "%s" "$_str_c"
      ;;
    *)
      printf "%%%02X" "'$_str_c"
      ;;
    esac
    _u_i="$(_math "$_u_i" + 1)"
  done
}

_ali_nonce() {
  #_head_n 1 </dev/urandom | _digest "sha256" hex | cut -c 1-31
  #Not so good...
  date +"%s%N"
}

_check_exist_query() {
  _qdomain="$1"
  _qsubdomain="$2"
  query=''
  query=$query'AccessKeyId='$ALICLOUD_ACCESS_KEY
  query=$query'&Action=DescribeDomainRecords'
  query=$query'&DomainName='$_qdomain
  query=$query'&Format=json'
  query=$query'&RRKeyWord='$_qsubdomain
  if [ -n "$ALICLOUD_SECURITY_TOKEN" ]; then
    query=$query'&SecurityToken='$(_ali_urlencode "$ALICLOUD_SECURITY_TOKEN")
  fi
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&TypeKeyWord=TXT'
  query=$query'&Version=2015-01-09'
}

_add_record_query() {
  query=''
  query=$query'AccessKeyId='$ALICLOUD_ACCESS_KEY
  query=$query'&Action=AddDomainRecord'
  query=$query'&DomainName='$1
  query=$query'&Format=json'
  query=$query'&RR='$2
  if [ -n "$ALICLOUD_SECURITY_TOKEN" ]; then
    query=$query'&SecurityToken='$(_ali_urlencode "$ALICLOUD_SECURITY_TOKEN")
  fi
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&Type=TXT'
  query=$query'&Value='$3
  query=$query'&Version=2015-01-09'
}

_delete_record_query() {
  query=''
  query=$query'AccessKeyId='$ALICLOUD_ACCESS_KEY
  query=$query'&Action=DeleteDomainRecord'
  query=$query'&Format=json'
  query=$query'&RecordId='$1
  if [ -n "$ALICLOUD_SECURITY_TOKEN" ]; then
    query=$query'&SecurityToken='$(_ali_urlencode "$ALICLOUD_SECURITY_TOKEN")
  fi
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&Version=2015-01-09'
}

_describe_records_query() {
  query=''
  query=$query'AccessKeyId='$ALICLOUD_ACCESS_KEY
  query=$query'&Action=DescribeDomainRecords'
  query=$query'&DomainName='$1
  query=$query'&Format=json'
  if [ -n "$ALICLOUD_SECURITY_TOKEN" ]; then
    query=$query'&SecurityToken='$(_ali_urlencode "$ALICLOUD_SECURITY_TOKEN")
  fi
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&Version=2015-01-09'
}

_clean() {
  _check_exist_query "$_domain" "$_sub_domain"
  # do not correct grammar here
  if ! _ali_rest "Check exist records" "ignore"; then
    return 1
  fi

  record_id="$(echo "$response" | tr '{' "\n" | grep "$_sub_domain" | grep -- "$txtvalue" | tr "," "\n" | grep RecordId | cut -d '"' -f 4)"
  _debug2 record_id "$record_id"

  if [ -z "$record_id" ]; then
    _debug "record not found, skip"
  else
    _delete_record_query "$record_id"
    _ali_rest "Delete record $record_id" "ignore"
  fi

}

_timestamp() {
  date -u +"%Y-%m-%dT%H%%3A%M%%3A%SZ"
}
