#!/usr/bin/env sh

#
#AWS_ACCESS_KEY_ID="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#AWS_SECRET_ACCESS_KEY="xxxxxxx"

#This is the Amazon Route53 api wrapper for acme.sh
#All `_sleep` commands are included to avoid Route53 throttling, see
#https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/DNSLimitations.html#limits-api-requests

AWS_HOST="route53.amazonaws.com"
AWS_URL="https://$AWS_HOST"

AWS_WIKI="https://github.com/acmesh-official/acme.sh/wiki/How-to-use-Amazon-Route53-API"

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_aws_add() {
  fulldomain=$1
  txtvalue=$2

  AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$(_readaccountconf_mutable AWS_ACCESS_KEY_ID)}"
  AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$(_readaccountconf_mutable AWS_SECRET_ACCESS_KEY)}"
  AWS_DNS_SLOWRATE="${AWS_DNS_SLOWRATE:-$(_readaccountconf_mutable AWS_DNS_SLOWRATE)}"

  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    _use_container_role || _use_instance_role
  fi

  # if not already set, attempt to get AWS creds from a local creds file.
  # this is naive, it just grabs the first values from .aws/credentials
  # it does not honour [sections] in the ini formatted credentials file.
  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    CREDFILE="${HOME}/.aws/credentials"
    if [ -e "$CREDFILE" ]; then
      AWS_ACCESS_KEY_ID=$(grep -m 1 -i AWS_ACCESS_KEY_ID "$CREDFILE" | cut -f 2 -d"=" | tr -d ' ')
      AWS_SECRET_ACCESS_KEY=$(grep -m 1 -i AWS_SECRET_ACCESS_KEY "$CREDFILE" | cut -f 2 -d"=" | tr -d ' ')
    fi
    # todo: if the key is found in the creds file, then if we can assume it'll be there in the future,
    # then there's likely no point saving it in the account config, so we should do what needs to be done
    # to disable saving the AWS creds in the acme.sh config.
  fi
  
  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    AWS_ACCESS_KEY_ID=""
    AWS_SECRET_ACCESS_KEY=""
    _err "You haven't specifed the aws route53 api key id and and api key secret yet."
    _err "Please create your key and try again. see $(__green $AWS_WIKI)"
    return 1
  fi

  #save for future use, unless using a role which will be fetched as needed
  if [ -z "$_using_role" ]; then
    _saveaccountconf_mutable AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID"
    _saveaccountconf_mutable AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"
    _saveaccountconf_mutable AWS_DNS_SLOWRATE "$AWS_DNS_SLOWRATE"
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    _sleep 1
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Getting existing records for $fulldomain"
  if ! aws_rest GET "2013-04-01$_domain_id/rrset" "name=$fulldomain&type=TXT"; then
    _sleep 1
    return 1
  fi

  if _contains "$response" "<Name>$fulldomain.</Name>"; then
    _resource_record="$(echo "$response" | sed 's/<ResourceRecordSet>/"/g' | tr '"' "\n" | grep "<Name>$fulldomain.</Name>" | _egrep_o "<ResourceRecords.*</ResourceRecords>" | sed "s/<ResourceRecords>//" | sed "s#</ResourceRecords>##")"
    _debug "_resource_record" "$_resource_record"
  else
    _debug "single new add"
  fi

  if [ "$_resource_record" ] && _contains "$response" "$txtvalue"; then
    _info "The TXT record already exists. Skipping."
    _sleep 1
    return 0
  fi

  _debug "Adding records"

  _aws_tmpl_xml="<ChangeResourceRecordSetsRequest xmlns=\"https://route53.amazonaws.com/doc/2013-04-01/\"><ChangeBatch><Changes><Change><Action>UPSERT</Action><ResourceRecordSet><Name>$fulldomain</Name><Type>TXT</Type><TTL>300</TTL><ResourceRecords>$_resource_record<ResourceRecord><Value>\"$txtvalue\"</Value></ResourceRecord></ResourceRecords></ResourceRecordSet></Change></Changes></ChangeBatch></ChangeResourceRecordSetsRequest>"

  if aws_rest POST "2013-04-01$_domain_id/rrset/" "" "$_aws_tmpl_xml" && _contains "$response" "ChangeResourceRecordSetsResponse"; then
    _info "TXT record updated successfully."
    if [ -n "$AWS_DNS_SLOWRATE" ]; then
      _info "Slow rate activated: sleeping for $AWS_DNS_SLOWRATE seconds"
      _sleep "$AWS_DNS_SLOWRATE"
    else
      _sleep 1
    fi

    return 0
  fi
  _sleep 1
  return 1
}

#fulldomain txtvalue
dns_aws_rm() {
  fulldomain=$1
  txtvalue=$2

  AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$(_readaccountconf_mutable AWS_ACCESS_KEY_ID)}"
  AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$(_readaccountconf_mutable AWS_SECRET_ACCESS_KEY)}"
  AWS_DNS_SLOWRATE="${AWS_DNS_SLOWRATE:-$(_readaccountconf_mutable AWS_DNS_SLOWRATE)}"

  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    _use_container_role || _use_instance_role
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    _sleep 1
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Getting existing records for $fulldomain"
  if ! aws_rest GET "2013-04-01$_domain_id/rrset" "name=$fulldomain&type=TXT"; then
    _sleep 1
    return 1
  fi

  if _contains "$response" "<Name>$fulldomain.</Name>"; then
    _resource_record="$(echo "$response" | sed 's/<ResourceRecordSet>/"/g' | tr '"' "\n" | grep "<Name>$fulldomain.</Name>" | _egrep_o "<ResourceRecords.*</ResourceRecords>" | sed "s/<ResourceRecords>//" | sed "s#</ResourceRecords>##")"
    _debug "_resource_record" "$_resource_record"
  else
    _debug "no records exist, skip"
    _sleep 1
    return 0
  fi

  _aws_tmpl_xml="<ChangeResourceRecordSetsRequest xmlns=\"https://route53.amazonaws.com/doc/2013-04-01/\"><ChangeBatch><Changes><Change><Action>DELETE</Action><ResourceRecordSet><ResourceRecords>$_resource_record</ResourceRecords><Name>$fulldomain.</Name><Type>TXT</Type><TTL>300</TTL></ResourceRecordSet></Change></Changes></ChangeBatch></ChangeResourceRecordSetsRequest>"

  if aws_rest POST "2013-04-01$_domain_id/rrset/" "" "$_aws_tmpl_xml" && _contains "$response" "ChangeResourceRecordSetsResponse"; then
    _info "TXT record deleted successfully."
    if [ -n "$AWS_DNS_SLOWRATE" ]; then
      _info "Slow rate activated: sleeping for $AWS_DNS_SLOWRATE seconds"
      _sleep "$AWS_DNS_SLOWRATE"
    else
      _sleep 1
    fi

    return 0
  fi
  _sleep 1
  return 1

}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  i=2
  p=1

  if aws_rest GET "2013-04-01/hostedzone"; then
    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f $i-100)
      _debug2 "Checking domain: $h"
      if [ -z "$h" ]; then
        if _contains "$response" "<IsTruncated>true</IsTruncated>" && _contains "$response" "<NextMarker>"; then
          _debug "IsTruncated"
          _nextMarker="$(echo "$response" | _egrep_o "<NextMarker>.*</NextMarker>" | cut -d '>' -f 2 | cut -d '<' -f 1)"
          _debug "NextMarker" "$_nextMarker"
          if aws_rest GET "2013-04-01/hostedzone" "marker=$_nextMarker"; then
            _debug "Truncated request OK"
            i=2
            p=1
            continue
          else
            _err "Truncated request error."
          fi
        fi
        #not valid
        _err "Invalid domain"
        return 1
      fi

      if _contains "$response" "<Name>$h.</Name>"; then
        hostedzone="$(echo "$response" | sed 's/<HostedZone>/#&/g' | tr '#' '\n' | _egrep_o "<HostedZone><Id>[^<]*<.Id><Name>$h.<.Name>.*<PrivateZone>false<.PrivateZone>.*<.HostedZone>")"
        _debug hostedzone "$hostedzone"
        if [ "$hostedzone" ]; then
          _domain_id=$(printf "%s\n" "$hostedzone" | _egrep_o "<Id>.*<.Id>" | head -n 1 | _egrep_o ">.*<" | tr -d "<>")
          if [ "$_domain_id" ]; then
            _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
            _domain=$h
            return 0
          fi
          _err "Can't find domain with id: $h"
          return 1
        fi
      fi
      p=$i
      i=$(_math "$i" + 1)
    done
  fi
  return 1
}

_use_container_role() {
  # automatically set if running inside ECS
  if [ -z "$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" ]; then
    _debug "No ECS environment variable detected"
    return 1
  fi
  _use_metadata "169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
}

_use_instance_role() {
  _url="http://169.254.169.254/latest/meta-data/iam/security-credentials/"
  _debug "_url" "$_url"
  if ! _get "$_url" true 1 | _head_n 1 | grep -Fq 200; then
    _debug "Unable to fetch IAM role from instance metadata"
    return 1
  fi
  _aws_role=$(_get "$_url" "" 1)
  _debug "_aws_role" "$_aws_role"
  _use_metadata "$_url$_aws_role"
}

_use_metadata() {
  _aws_creds="$(
    _get "$1" "" 1 |
      _normalizeJson |
      tr '{,}' '\n' |
      while read -r _line; do
        _key="$(echo "${_line%%:*}" | tr -d '"')"
        _value="${_line#*:}"
        _debug3 "_key" "$_key"
        _secure_debug3 "_value" "$_value"
        case "$_key" in
        AccessKeyId) echo "AWS_ACCESS_KEY_ID=$_value" ;;
        SecretAccessKey) echo "AWS_SECRET_ACCESS_KEY=$_value" ;;
        Token) echo "AWS_SESSION_TOKEN=$_value" ;;
        esac
      done |
      paste -sd' ' -
  )"
  _secure_debug "_aws_creds" "$_aws_creds"

  if [ -z "$_aws_creds" ]; then
    return 1
  fi

  eval "$_aws_creds"
  _using_role=true
}

#method uri qstr data
aws_rest() {
  mtd="$1"
  ep="$2"
  qsr="$3"
  data="$4"

  _debug mtd "$mtd"
  _debug ep "$ep"
  _debug qsr "$qsr"
  _debug data "$data"

  CanonicalURI="/$ep"
  _debug2 CanonicalURI "$CanonicalURI"

  CanonicalQueryString="$qsr"
  _debug2 CanonicalQueryString "$CanonicalQueryString"

  RequestDate="$(date -u +"%Y%m%dT%H%M%SZ")"
  _debug2 RequestDate "$RequestDate"

  #RequestDate="20161120T141056Z" ##############

  export _H1="x-amz-date: $RequestDate"

  aws_host="$AWS_HOST"
  CanonicalHeaders="host:$aws_host\nx-amz-date:$RequestDate\n"
  SignedHeaders="host;x-amz-date"
  if [ -n "$AWS_SESSION_TOKEN" ]; then
    export _H3="x-amz-security-token: $AWS_SESSION_TOKEN"
    CanonicalHeaders="${CanonicalHeaders}x-amz-security-token:$AWS_SESSION_TOKEN\n"
    SignedHeaders="${SignedHeaders};x-amz-security-token"
  fi
  _debug2 CanonicalHeaders "$CanonicalHeaders"
  _debug2 SignedHeaders "$SignedHeaders"

  RequestPayload="$data"
  _debug2 RequestPayload "$RequestPayload"

  Hash="sha256"

  CanonicalRequest="$mtd\n$CanonicalURI\n$CanonicalQueryString\n$CanonicalHeaders\n$SignedHeaders\n$(printf "%s" "$RequestPayload" | _digest "$Hash" hex)"
  _debug2 CanonicalRequest "$CanonicalRequest"

  HashedCanonicalRequest="$(printf "$CanonicalRequest%s" | _digest "$Hash" hex)"
  _debug2 HashedCanonicalRequest "$HashedCanonicalRequest"

  Algorithm="AWS4-HMAC-SHA256"
  _debug2 Algorithm "$Algorithm"

  RequestDateOnly="$(echo "$RequestDate" | cut -c 1-8)"
  _debug2 RequestDateOnly "$RequestDateOnly"

  Region="us-east-1"
  Service="route53"

  CredentialScope="$RequestDateOnly/$Region/$Service/aws4_request"
  _debug2 CredentialScope "$CredentialScope"

  StringToSign="$Algorithm\n$RequestDate\n$CredentialScope\n$HashedCanonicalRequest"

  _debug2 StringToSign "$StringToSign"

  kSecret="AWS4$AWS_SECRET_ACCESS_KEY"

  #kSecret="wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY" ############################

  _secure_debug2 kSecret "$kSecret"

  kSecretH="$(printf "%s" "$kSecret" | _hex_dump | tr -d " ")"
  _secure_debug2 kSecretH "$kSecretH"

  kDateH="$(printf "$RequestDateOnly%s" | _hmac "$Hash" "$kSecretH" hex)"
  _debug2 kDateH "$kDateH"

  kRegionH="$(printf "$Region%s" | _hmac "$Hash" "$kDateH" hex)"
  _debug2 kRegionH "$kRegionH"

  kServiceH="$(printf "$Service%s" | _hmac "$Hash" "$kRegionH" hex)"
  _debug2 kServiceH "$kServiceH"

  kSigningH="$(printf "%s" "aws4_request" | _hmac "$Hash" "$kServiceH" hex)"
  _debug2 kSigningH "$kSigningH"

  signature="$(printf "$StringToSign%s" | _hmac "$Hash" "$kSigningH" hex)"
  _debug2 signature "$signature"

  Authorization="$Algorithm Credential=$AWS_ACCESS_KEY_ID/$CredentialScope, SignedHeaders=$SignedHeaders, Signature=$signature"
  _debug2 Authorization "$Authorization"

  _H2="Authorization: $Authorization"
  _debug _H2 "$_H2"

  url="$AWS_URL/$ep"
  if [ "$qsr" ]; then
    url="$AWS_URL/$ep?$qsr"
  fi

  if [ "$mtd" = "GET" ]; then
    response="$(_get "$url")"
  else
    response="$(_post "$data" "$url")"
  fi

  _ret="$?"
  _debug2 response "$response"
  if [ "$_ret" = "0" ]; then
    if _contains "$response" "<ErrorResponse"; then
      _err "Response error:$response"
      return 1
    fi
  fi

  return "$_ret"
}
