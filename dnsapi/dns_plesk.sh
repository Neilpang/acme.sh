#!/usr/bin/env sh

#
#PLESK_Host="host.com"
#
#PLESK_User="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#PLESK_Password="xxxx@sss.com"


########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_plesk_add() {
  fulldomain=$1
  txtvalue=$2

  PLESK_Host="${CF_Key:-$(_readaccountconf_mutable PLESK_Host)}"
  PLESK_User="${CF_Key:-$(_readaccountconf_mutable PLESK_User)}"
  PLESK_Password="${CF_Key:-$(_readaccountconf_mutable PLESK_Password)}"

  if [ -z "$PLESK_Host" ] || [ -z "$PLESK_User" ] || [ -z "$PLESK_Password"]; then
    PLESK_Host=""
    PLESK_User=""
    PLESK_Password=""
    _err "You didn't specify a plesk credentials yet."
    _err "Please create the key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable PLESK_Host "$PLESK_Host"
  _saveaccountconf_mutable PLESK_User "$PLESK_User"
  _saveaccountconf_mutable PLESK_Password "$PLESK_Password"
 
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  add_txt_record $_domain_id $_sub_domain $txtvalue
  
}

#fulldomain txtvalue
dns_plesk_rm() {
  fulldomain=$1
  txtvalue=$2

  PLESK_Host="${CF_Key:-$(_readaccountconf_mutable PLESK_Host)}"
  PLESK_User="${CF_Key:-$(_readaccountconf_mutable PLESK_User)}"
  PLESK_Password="${CF_Key:-$(_readaccountconf_mutable PLESK_Password)}"

  if [ -z "$PLESK_Host" ] || [ -z "$PLESK_User" ] || [ -z "$PLESK_Password"]; then
    PLESK_Host=""
    PLESK_User=""
    PLESK_Password=""
    _err "You didn't specify a plesk credentials yet."
    _err "Please create the key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable PLESK_Host "$PLESK_Host"
  _saveaccountconf_mutable PLESK_User "$PLESK_User"
  _saveaccountconf_mutable PLESK_Password "$PLESK_Password"
  
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Remove record"
  del_txt_record $_domain_id $fulldomain
}


function plesk_api() {
    local request="$1"

    export _H1="HTTP_AUTH_LOGIN: $PLESK_User"
    export _H2="HTTP_AUTH_PASSWD: $PLESK_Password"
    export _H3="content-Type: text/xml"
    export _H4="HTTP_PRETTY_PRINT: true"

    response="$(_post $request "https://$PLESK_Host:8443/enterprise/control/agent.php" "" "POST")"
    _debug2 "response" "$response"
    return 0

}

function add_txt_record() {
    local site_id=$1
    local subdomain=$2
    local txt_value=$3
    local request="<packet><dns><add_rec><site-id>$site_id</site-id><type>TXT</type><host>$subdomain</host><value>$txt_value</value></add_rec></dns></packet>"
    plesk_api $request

    if ! _contains "${response}" '<status>ok</status>'; then
        return 1
    fi
    return 0
}

function del_txt_record() {
    local site_id=$1
    local fulldomain="${2}."
    
    get_dns_record_list $site_id

    j=0
    for item in "${_plesk_dns_host[@]}"
    do
      _debug "item" $item
      if [  "$fulldomain" = "$item" ]; then
        _dns_record_id=${_plesk_dns_ids[$j]}
      fi
      j=$(_math "$j" +1)
    done

    _debug "record id" "$_dns_record_id"
    local request="<packet><dns><del_rec><filter><id>$_dns_record_id</id></filter></del_rec></dns></packet>"
    plesk_api $request

    if ! _contains "${response}" '<status>ok</status>'; then
        return 1
    fi
    return 0
}

function get_domain_list() {
  local request='<packet><customer><get-domain-list><filter></filter></get-domain-list></customer></packet>'
  
  plesk_api $request

  if ! _contains "${response}" '<status>ok</status>'; then
    return 1
  fi

  _plesk_domain_names=($(echo "${response}" | sed -nr 's_<name>(.*)</name>_\1_p'));
  _plesk_domain_ids=($(echo "${response}"| sed -nr 's_<id>(.*)</id>_\1_p'));
  _plesk_domain_ids=("${_plesk_domain_ids[@]:1}")
  
}

function get_dns_record_list() {
  local siteid=$1
  local request="<packet><dns><get_rec><filter><site-id>$siteid</site-id></filter></get_rec></dns></packet>"
  
  plesk_api $request

  if ! _contains "${response}" '<status>ok</status>'; then
    return 1
  fi

  _plesk_dns_host=($(echo "${response}" | sed -nr 's_<host>(.*)</host>_\1_p'));
  _plesk_dns_ids=($(echo "${response}"| sed -nr 's_<id>(.*)</id>_\1_p'));
  
}

 #urls=($(sed -nr 's_<id>(.*)</id>_\1_p' resp.txt)); echo ${urls[@]}

#domain.com
#returns
# _plesk_site_id=22
function get_site_id() {
    local site_name=$1
    request="<packet><site><get><filter><name>$site_name</name></filter><dataset><gen_info/></dataset></get></site></packet>"
    plesk_api $request
    echo $resonse
    _plesk_site_id="$(echo $response | grep -Po '(?<=<id>).*?(?=</id>)')"
    return 0
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=2
  p=1

  get_domain_list

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi
    
    j=0
    for item in "${_plesk_domain_names[@]}"
    do
      _debug "item" $item
      if [  "$h" = "$item" ]; then
        
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
        _domain="$h"
        _domain_id=${_plesk_domain_ids[$j]}
        return 0
      fi
      j=$(_math "$j" +1)
    done
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

