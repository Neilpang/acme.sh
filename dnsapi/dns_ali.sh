#!/usr/bin/env sh

Ali_API="https://alidns.aliyuncs.com/"

#Ali_Key="LTqIA87hOKdjevsf5"
#Ali_Secret="0p5EYueFNq501xnCPzKNbx6K51qPH2"

#Usage: dns_ali_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ali_add() {
  fulldomain=$1
  txtvalue=$2

  Ali_Key="${Ali_Key:-$(_readaccountconf_mutable Ali_Key)}"
  Ali_Secret="${Ali_Secret:-$(_readaccountconf_mutable Ali_Secret)}"
  if [ -z "$Ali_Key" ] || [ -z "$Ali_Secret" ]; then
    Ali_Key=""
    Ali_Secret=""
    _err "You don't specify aliyun api key and secret yet."
    return 1
  fi

  #save the api key and secret to the account conf file.
  _saveaccountconf_mutable Ali_Key "$Ali_Key"
  _saveaccountconf_mutable Ali_Secret "$Ali_Secret"

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
  Ali_Key="${Ali_Key:-$(_readaccountconf_mutable Ali_Key)}"
  Ali_Secret="${Ali_Secret:-$(_readaccountconf_mutable Ali_Secret)}"

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

_ali_rest() {
  _sign_str=$(printf "%s" "GET&%2F&$(_ali_urlencode "$query")")
  _debug2 _sign_str _sign_str
  signature=$(printf "%s" "$_sign_str" | _hmac "sha1" "$(printf "%s" "$Ali_Secret&" | _hex_dump | tr -d " ")" | _base64)
  signature=$(_ali_urlencode "$signature")
  _debug2 signature "$signature"
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

_ali_url_encode() {
  _hex_str=$(_hex_dump)
  _debug3 "_url_encode"
  _debug3 "_hex_str" "$_hex_str"
  for _hex_code in $_hex_str; do
    #upper case
    case "${_hex_code}" in
      "41")
        printf "%s" "A"
        ;;
      "42")
        printf "%s" "B"
        ;;
      "43")
        printf "%s" "C"
        ;;
      "44")
        printf "%s" "D"
        ;;
      "45")
        printf "%s" "E"
        ;;
      "46")
        printf "%s" "F"
        ;;
      "47")
        printf "%s" "G"
        ;;
      "48")
        printf "%s" "H"
        ;;
      "49")
        printf "%s" "I"
        ;;
      "4a")
        printf "%s" "J"
        ;;
      "4b")
        printf "%s" "K"
        ;;
      "4c")
        printf "%s" "L"
        ;;
      "4d")
        printf "%s" "M"
        ;;
      "4e")
        printf "%s" "N"
        ;;
      "4f")
        printf "%s" "O"
        ;;
      "50")
        printf "%s" "P"
        ;;
      "51")
        printf "%s" "Q"
        ;;
      "52")
        printf "%s" "R"
        ;;
      "53")
        printf "%s" "S"
        ;;
      "54")
        printf "%s" "T"
        ;;
      "55")
        printf "%s" "U"
        ;;
      "56")
        printf "%s" "V"
        ;;
      "57")
        printf "%s" "W"
        ;;
      "58")
        printf "%s" "X"
        ;;
      "59")
        printf "%s" "Y"
        ;;
      "5a")
        printf "%s" "Z"
        ;;

      #lower case
      "61")
        printf "%s" "a"
        ;;
      "62")
        printf "%s" "b"
        ;;
      "63")
        printf "%s" "c"
        ;;
      "64")
        printf "%s" "d"
        ;;
      "65")
        printf "%s" "e"
        ;;
      "66")
        printf "%s" "f"
        ;;
      "67")
        printf "%s" "g"
        ;;
      "68")
        printf "%s" "h"
        ;;
      "69")
        printf "%s" "i"
        ;;
      "6a")
        printf "%s" "j"
        ;;
      "6b")
        printf "%s" "k"
        ;;
      "6c")
        printf "%s" "l"
        ;;
      "6d")
        printf "%s" "m"
        ;;
      "6e")
        printf "%s" "n"
        ;;
      "6f")
        printf "%s" "o"
        ;;
      "70")
        printf "%s" "p"
        ;;
      "71")
        printf "%s" "q"
        ;;
      "72")
        printf "%s" "r"
        ;;
      "73")
        printf "%s" "s"
        ;;
      "74")
        printf "%s" "t"
        ;;
      "75")
        printf "%s" "u"
        ;;
      "76")
        printf "%s" "v"
        ;;
      "77")
        printf "%s" "w"
        ;;
      "78")
        printf "%s" "x"
        ;;
      "79")
        printf "%s" "y"
        ;;
      "7a")
        printf "%s" "z"
        ;;
      #numbers
      "30")
        printf "%s" "0"
        ;;
      "31")
        printf "%s" "1"
        ;;
      "32")
        printf "%s" "2"
        ;;
      "33")
        printf "%s" "3"
        ;;
      "34")
        printf "%s" "4"
        ;;
      "35")
        printf "%s" "5"
        ;;
      "36")
        printf "%s" "6"
        ;;
      "37")
        printf "%s" "7"
        ;;
      "38")
        printf "%s" "8"
        ;;
      "39")
        printf "%s" "9"
        ;;
      "2d")
        printf "%s" "-"
        ;;
      "5f")
        printf "%s" "_"
        ;;
      "2e")
        printf "%s" "."
        ;;
      "7e")
        printf "%s" "~"
        ;;
      #other hex
      *)
        printf '%%%s' "$_hex_code" | tr '[:lower:]' '[:upper:]'
        ;;
    esac
  done
}

_ali_urlencode() {
  _str=$(printf "%s" "$1" | _ali_url_encode)
  printf "%s" "$_str"
}

_ali_nonce() {
  #_head_n 1 </dev/urandom | _digest "sha256" hex | cut -c 1-31
  #Not so good...
  date +"%s%N"
}

_check_exist_query() {
  _qdomain=$(_ali_urlencode "$1")
  _qsubdomain=$(_ali_urlencode "$2")
  query=''
  query=$query'AccessKeyId='$Ali_Key
  query=$query'&Action=DescribeDomainRecords'
  query=$query'&DomainName='$_qdomain
  query=$query'&Format=json'
  query=$query'&RRKeyWord='$_qsubdomain
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&TypeKeyWord=TXT'
  query=$query'&Version=2015-01-09'
}

_add_record_query() {
  query=''
  query=$query'AccessKeyId='$Ali_Key
  query=$query'&Action=AddDomainRecord'
  query=$query'&DomainName='$(_ali_urlencode "$1")
  query=$query'&Format=json'
  query=$query'&RR='$2
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
  query=$query'AccessKeyId='$Ali_Key
  query=$query'&Action=DeleteDomainRecord'
  query=$query'&Format=json'
  query=$query'&RecordId='$1
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_timestamp)
  query=$query'&Version=2015-01-09'
}

_describe_records_query() {
  query=''
  query=$query'AccessKeyId='$Ali_Key
  query=$query'&Action=DescribeDomainRecords'
  query=$query'&DomainName='$(_ali_urlencode "$1")
  query=$query'&Format=json'
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
