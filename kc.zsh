# kc - fast kubeconfig + namespace switcher (zsh, macOS)
#
# Usage:
#   kc                 list configs and namespaces, marking the active one
#   kc nonprod         switch to nonprod (default namespace: aqeelta-dt)
#   kc prod            switch to prod (default namespace: aqeelta-stage)
#   kc prod aqeelta-prod   switch and pick a namespace
#   kc ns <name>       change namespace within the active config
#   kc -               toggle back to the previous config
#
# Load it by adding this to ~/.zshrc (after compinit, if you use it):
#   source ~/.kube/kc.zsh

typeset -gA _KC_FILE _KC_NSLIST
_KC_ORDER=(nonprod prod)
_KC_FILE=(
  nonprod "$HOME/.kube/esb-nonprod-internal.yaml"
  prod    "$HOME/.kube/esb-prod-internal.yaml"
)
# The first namespace in each list is the default when you switch.
_KC_NSLIST=(
  nonprod "aqeelta-dt aqeelta-int aqeelta-uat"
  prod    "aqeelta-stage aqeelta-prod"
)

_kc_help() {
  cat <<'EOF'
kc                     list configs and namespaces
kc <nonprod|prod> [ns] switch config (and optionally namespace)
kc ns <name>           change namespace in the active config
kc -                   toggle to the previous config
EOF
}

_kc_list() {
  local name ns mark
  for name in $_KC_ORDER; do
    mark=" "; [[ $name == $KC_NAME ]] && mark="*"
    echo "$mark $name  ($_KC_FILE[$name:t])"
    for ns in ${=_KC_NSLIST[$name]}; do
      if [[ $name == $KC_NAME && $ns == $KC_NS ]]; then
        echo "      > $ns"
      else
        echo "        $ns"
      fi
    done
  done
}

_kc_status() {
  local ctx
  ctx=$(kubectl config current-context 2>/dev/null)
  echo "kc: ${KC_NAME}  context=${ctx:-?}  namespace=${KC_NS}"
}

_kc_setns() {
  local ns="$1"
  if [[ -z $KC_NAME ]]; then
    echo "kc: no active config. Run 'kc nonprod' or 'kc prod' first." >&2
    return 1
  fi
  if [[ -z $ns ]]; then
    echo "kc: usage: kc ns <name>  (valid: ${_KC_NSLIST[$KC_NAME]})" >&2
    return 1
  fi
  local -a nss=(${=_KC_NSLIST[$KC_NAME]})
  if (( ! ${nss[(Ie)$ns]} )); then
    echo "kc: '$ns' is not a namespace for $KC_NAME (valid: ${nss[*]})" >&2
    return 1
  fi
  kubectl config set-context --current --namespace="$ns" >/dev/null || {
    echo "kc: failed to set namespace; active config unchanged" >&2
    return 1
  }
  export KC_NS="$ns"
  _kc_status
}

kc() {
  local arg="$1" ns="$2"

  case "$arg" in
    "")        _kc_list; return 0 ;;
    -h|--help) _kc_help; return 0 ;;
    ns)        _kc_setns "$2"; return $? ;;
    -)
      if [[ -z $KC_PREV ]]; then
        echo "kc: no previous config to toggle to" >&2
        return 1
      fi
      arg="$KC_PREV"
      ns=""
      ;;
  esac

  local file="${_KC_FILE[$arg]}"
  if [[ -z $file ]]; then
    echo "kc: unknown config '$arg' (use: ${_KC_ORDER[*]})" >&2
    return 1
  fi
  if [[ ! -r $file ]]; then
    echo "kc: cannot read $file; active config unchanged" >&2
    return 1
  fi

  local -a nss=(${=_KC_NSLIST[$arg]})
  [[ -z $ns ]] && ns="${nss[1]}"
  if (( ! ${nss[(Ie)$ns]} )); then
    echo "kc: '$ns' is not a namespace for $arg (valid: ${nss[*]})" >&2
    return 1
  fi

  # Remember where we came from, but only when actually changing config.
  local prev="$KC_NAME"
  export KUBECONFIG="$file"
  if ! kubectl config set-context --current --namespace="$ns" >/dev/null; then
    echo "kc: could not set namespace in $file (does it have a current-context?)" >&2
    return 1
  fi
  [[ -n $prev && $prev != $arg ]] && export KC_PREV="$prev"
  export KC_NAME="$arg" KC_NS="$ns"
  _kc_status
}

# --- Prompt indicator: green for nonprod, bold red for prod ---
_kc_precmd() {
  if [[ -n $KC_NAME ]]; then
    if [[ $KC_NAME == prod ]]; then
      KC_PROMPT="%B%F{red}[${KC_NAME}:${KC_NS}]%f%b "
    else
      KC_PROMPT="%F{green}[${KC_NAME}:${KC_NS}]%f "
    fi
  else
    KC_PROMPT=""
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook -d precmd _kc_precmd 2>/dev/null
add-zsh-hook precmd _kc_precmd
setopt PROMPT_SUBST
[[ $PROMPT != *'${KC_PROMPT}'* ]] && PROMPT='${KC_PROMPT}'"$PROMPT"

# --- Tab completion ---
_kc_complete() {
  local -a opts
  if (( CURRENT == 2 )); then
    opts=($_KC_ORDER ns -)
  elif (( CURRENT == 3 )); then
    if [[ $words[2] == ns ]]; then
      opts=(${=_KC_NSLIST[$KC_NAME]})
    elif [[ -n ${_KC_NSLIST[$words[2]]} ]]; then
      opts=(${=_KC_NSLIST[$words[2]]})
    fi
  fi
  compadd -a opts
}
(( $+functions[compdef] )) && compdef _kc_complete kc
