# vim: ft=sh
# Command completion for Yeoman
# by Michael Ichnowski

# Default value for $NODE_PATH - a one-off performance penalty only
# incurred if $NODE_PATH has not been set
: ${NODE_PATH:=$( npm -g root )}

__yo_node_path() {
  local IFS p

  case $OSTYPE in
    *cygwin*|*msys*) IFS=';' ;; # Windows
    *)               IFS=':' ;; # Unix
  esac

  for p in $NODE_PATH; do echo "$p"; done
  echo "$PWD/node_modules"
}

__yo_ltrim_colon_completions() {
  # If word-to-complete contains a colon,
  # and bash-version < 4,
  # or bash-version >= 4 and COMP_WORDBREAKS contains a colon
  local -r cur=$1
  if [[
      $cur == *:* && (
        ${BASH_VERSINFO[0]} -lt 4 ||
        (${BASH_VERSINFO[0]} -ge 4 && "$COMP_WORDBREAKS" == *:*)
      )
  ]]; then
    # Remove word-colon prefix from COMPREPLY items
    local i=${#COMPREPLY[*]}
    local -r prefix=${cur%${cur##*:}}

    while [ $((--i)) -ge 0 ]; do
      item=${COMPREPLY[$i]}
      COMPREPLY[$i]=${item#$prefix}
    done
  fi
}

_yo_generators() {
  local -r IFS=$'\n'

  for i in $( __yo_node_path ); do
    ls -d "$i"/generator-*/{,generators/}*/index.js 2>/dev/null
  done | sed 's/.*generator-//;s|/index.js$||' | sort | uniq | tr '/' ':'
}

__yo_gen_path() {
  local -r IFS=$'\n'
  local gen subgen

  gen=${1%:*}      # if $1='a:b', then $gen='a'
  if [[ $1 == *:* ]]; then
    subgen=${1#*:} # if $1='a:b', then $subgen='b'
  else
    subgen='app'   # set default value
  fi

  for i in $( __yo_node_path ); do
    if [ -e "$i"/generator-"$gen"/"$subgen"/index.js ]; then
       echo "$i/generator-$gen/$subgen"
       return 0
    elif [ -e "$i"/generator-"$gen"/generators/"$subgen"/index.js ]; then
       echo "$i/generator-$gen/generators/$subgen"
       return 0
    fi
  done
}

__yo_gen_opts() {
  local -r index="$1/index.js"

  sed -n "s/.*this\.option(.*'\([^']\+\)'.*/\1/p"  "$index" \
    | sort | uniq | sed 's/^/--/'
}

__yo_main_opts() {
  echo '
    --force --generators --help --insight
    --no-color --no-insight --version'
}

_yo_opts() {
  local path i=$1 words=( ${*:2} )

  while [ $(( --i )) -ge 1 ]; do
    path="$( __yo_gen_path "${words[$i]}" )"
    [ -n "$path" ] && echo "$( __yo_gen_opts "$path" )" && return
  done
  echo $( __yo_main_opts )
}

_yo() {
  local -r IFS=$'\n ' \
           EXCL=':='  # don't divide words on these characters

  local cur prev cword words
  COMPREPLY=()

  _get_comp_words_by_ref -n $EXCL cur prev cword words

    case "$cur" in
    -*)
      COMPREPLY=( $(compgen -W "$( _yo_opts "$cword" "${words[*]}" )" -- "$cur") )
      ;;
    *)
      COMPREPLY=( $(compgen -W  "$( _yo_generators )" -- "$cur") )
      __yo_ltrim_colon_completions "$cur"
    esac

  return 0
}

complete -F _yo yo
