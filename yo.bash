# Command completion for Yeoman
# by Michael Ichnowski

# Find the node_modules directory where 'yo' module itself is located
# @return  Physical path to the global node_modules directory
__yo_find_global_root() {
  local yo bin cli lib

  # No `readlink`? We're likely on Windows, so no links to read, anyway
  [ -n "$(which readlink)" ] || return

  yo=$( which yo )                      # e.g. ./node_modules/.bin/yo
  bin=${yo%/yo}                         #      ./node_modules/.bin
  cli=$( readlink "$yo" )               #      ../yo/lib/cli.js
  lib=$( cd "$bin/${cli%/*}"; pwd -P )  # ~/.local/lib/node_modules/yo/lib
  echo "${lib%/yo/lib}"                 # ~/.local/lib/node_modules
}

# @param $OSTYPE global string  System variable
# @param $APPDATA global string  System variable on MS Windows
# @param $NODE_PATH global string  Node.js variable with module locations
# @param $PWD global string  Current location in file system
# @stdout  List of newline-delimited Node.js module locations
__yo_node_path() {
  local IFS prefix root dir max_depth=20

  case $OSTYPE in
    *cygwin*|*msys*) IFS=';' prefix="$APPDATA/npm" ;; # Windows
    *)               IFS=':' prefix='/usr/lib'     ;; # Unix
  esac

  # search for local 'node_modules' paths here and up to $max_depth up
  dir=$PWD
  while [ "$dir" -a $(( max_depth-- )) -ge 0 ]; do
    [ -d "$dir/node_modules" ] && echo "$dir/node_modules"
    dir=${dir%/*}
  done

  if [ "$NODE_PATH" ]; then
    printf '%s\n' $NODE_PATH
  else
    root=$( __yo_find_global_root )
    [[ -n $root && $root != $prefix/node_modules ]] && echo "$root"
    [ -d "$prefix/node_modules" ] && echo "$prefix/node_modules"
  fi
}

# @stdin  List of newline-delimited file paths to read from
# @stdout  Concatenated contents of all files specified that exist
__yo_cat() {
  local file_name line

  while read -r file_name; do
    [ -f "$file_name" ] || continue
    while read -r line; do
      echo "$line"
    done < "$file_name"
  done
}

# Assign value to variable referenced by $1, but only if it's been set
# @param $1 string  Name of a variable to assign to
# @param $2 primitive  String/integer value to assign to the variable
# @modifies ${!1}  Variable referenced indirectly by $1, if set
__yo_up_var() {
  [ -n "${!1+set}" ] && eval "$1"'=$2'
}

# Assign array to variable referenced by $1, but only if it's been set
# @param $1 string  Name of a variable to assign to
# @param ${@:2} array  Array values to assign to the variable
# @modifies ${!1}  Variable referenced indirectly by $1, if set
__yo_up_arr() {
  [ -n "${!1+set}" ] && eval "$1"'=( "${@:2}" )'
}

# @param $COMP_LINE global string  Words entered so far
# @param $COMP_POINT global integer  Cursor position within $COMP_LINE
# @modifies $cur string  Current word to complete, up to cursor
# @modifies $cword integer  Index of the current word
# @modifies $words array  Words typed up to cursor
__yo_get_comp_words() {
  local _cur _cword _words \
    prev_char=${COMP_LINE:$(( COMP_POINT - 1 )):1}

  eval "_words=( ${COMP_LINE:0:$COMP_POINT} )"
  [ "$prev_char" == ' ' ] && _words+=( '' )

  _cword=$(( ${#_words[@]} - 1 ))
  _cur=${_words[$_cword]}

  __yo_up_var cur "$_cur"
  __yo_up_var cword $_cword
  __yo_up_arr words "${_words[@]}"
}

# Remove word-colon prefix from COMPREPLY items
# @param $1 string  Current word to complete (cur)
# @param $COMPREPLY global array  Completions prefixed with '<GENERATOR>:'
# @modifies $COMPREPLY global array  Generated completions
__yo_ltrim_colon_completions() {
  local item prefix \
    cur=$1 \
    i=${#COMPREPLY[@]}

  prefix=${cur%${cur##*:}}
  [ -z "$prefix" ] && return

  while [ $(( --i )) -ge 0 ]; do
    item=${COMPREPLY[$i]}
    COMPREPLY[$i]=${item#$prefix}
  done
}

# @param $1 string  Path containing any of /../, \..\, /./ or \.\
# @stdout  Normalised path
__yo_collapse_path() {
  local basename \
    dirname="${1%[/\\]*}"

  # if top-level directory given (e.g. /usr), print it and return
  # if only filename without path given, print it and return
  case $dirname in
    '') echo "$1" && return ;;
    $1) [ -d "$dirname" ] || echo "$1" && return
  esac

  basename="${1##*[/\\]}"

  [ -d "$dirname" ] && echo "$(cd "$dirname"; pwd)/${basename}"
}

# @param $1 string  (Sub)generator name, in the format 'aa' or 'aa:bb'
# @stdout  Path to the named (sub)generator's index.js file
__yo_gen_index() {
  local gen subgen p index \
    IFS=$'\n'

  gen=${1%:*}              # 'aa:bb' -> 'aa', 'aa' -> 'aa'
  if [[ $1 == *:* ]]; then
    subgen=${1#*:}         # 'aa:bb' -> 'bb'
  else
    subgen='app'           # set default value
  fi

  for p in $( __yo_node_path ); do
    for index in \
      "$p/generator-$gen/"{,{,lib/}generators/}"$subgen/index.js"; do

      [ -f "$index" ] && echo "$index" && return
    done
  done
}

# @param $1 string  List of newline-delimited paths to *.js files
# @stdout  List of paths to files required by files given
__yo_gen_required() {
  local path files file f \
    IFS=$'\n' \
    regex="s/.*require\([[:space:]]*['\"](\.[^'\"]+).*/\1/p"

  for path in $1; do
    [ -f "$path" ] || continue

    files=$( sed -En "$regex" "$path" )

    path=${path%[/\\]*}  # '/a/b' -> '/a', 'C:\a\b' -> 'C:\a'

    for file in $files; do
      for f in "${path}/${file}"{,.js}; do
        [ -f "$f" ] && __yo_collapse_path "$f" && break
      done
    done

  done | sort -u
}

# @param $1 string  Path to a (sub)generator's index.js file
# @stdout  List of (sub)generator's options (flags)
__yo_gen_opts() {
  local file required \
    yo_gen_base='../node_modules/yeoman-generator/lib/base.js' \
    index=$1 \
    regex1='/^[^*]{3}/' \
    regex1+="s/.*\.(option|hookFor)\([[:space:]]*['\"]([^'\"]+)" \
    regex1+='(.*(defaults:[[:space:]]+true))?.*/--\4\2/p' \
    regex2='s/--defaults:[[:space:]]+true(.*)/--no-\1/'

  if [ -f "$index" ]; then
    {
      for file in "${index%[/\\]*}"/{,../,../../}"$yo_gen_base"; do
        [ -f "$file" ] && echo "$file" && break
      done

      echo "$index"

      required=$( __yo_gen_required "$index" )$'\n'
      required+=$( __yo_gen_required "$required" )
      echo "$required"

    } | __yo_cat | tr ';\n' '\n ' | sed -En "$regex1" \
      | sed -E "$regex2"
  fi | sort -u
}

# @param $1 string  Name of a "usage" file to retrieve options from
# @stdout  Options (flags) retrieved from the file
__yo_parse_usage() {
  local usage=$1 \
    regex1='s/.*(--[^[:space:]]+).*/\1/p' \
    regex2='s/--\[no-\](.*)/--\1\n--no-\1/'

   sed -En "$regex1" "$usage" | sed -E "$regex2" | sort -u
}

# @stdout  Main command options (flags)
__yo_main_opts() {
  local p \
    IFS=$'\n' \
    usage='yo/lib/usage.txt'

  for p in $( __yo_node_path ); do
    [ -f "$p/$usage" ] && __yo_parse_usage "$p/$usage" && break
  done
}

# @param $1 integer  Index of the current word to complete (cword)
# @param ${@:2} array  Words typed so far (words); args start at ${@:3}
# @stdout  The 1st non-option argument up to cursor, if found,
#          empty string otherwise
__yo_first_arg() {
  local i words \
    cword=$1
  shift; words=( "$@" )

  # skip command name: ${words[0]}, and stop before current word
  for (( i=1; i < $cword; i++ )); do
    [[ ${words[$i]} == [^-]* ]] && echo "${words[$i]}" && return
  done
}

# @param $1 string  Current word to complete (cur)
# @param $2 integer  Index of the current word to complete (cword)
# @param ${@:3} array  Words typed so far (words)
# @stdout  Options (flags) for the main command or for a (sub)generator
_yo_opts() {
  local arg index opts \
    cur=$1 \
    cword=$2 \
    words=( "${@:3}" )

  arg=$( __yo_first_arg "$cword" "${words[@]}" )
  [ "$arg" == 'doctor' ] && return

  index=$( __yo_gen_index "$arg" )

  if [ -n "$index" ]; then
    opts=$( __yo_gen_opts "$index" )
  else
    opts=$( __yo_main_opts )
  fi

  __yo_compgen "$opts" "$cur"
  __yo_check_completed "$cur" && __yo_finish_word
}

# @param $1 string  Current word to complete (cur)
# @param $2 integer  Index of the current word to complete (cword)
# @param ${@:3} array  Words typed so far (words)
# @stdout  Names of sub-generators in the format 'aa:bb'
_yo_subgens() {
  local p index words subgens \
    IFS=$'\n' \
    cur=$1 \
    cword=$2 \
    regex='s/.*generator-([^/\]+)[/\]' \
    regex+='((lib[/\])?generators[/\])?' \
    regex+='([^/\]+)[/\]index\.js/\1:\4/p'

  shift 2; words=( "$@" )

  # only one generator allowed
  [ -n "$( __yo_first_arg "$cword" "${words[@]}" )" ] && return

  subgens=$(
    for p in $( __yo_node_path ); do
      for index in "$p"/generator-*/{,{,lib/}generators/}*/index.js; do
        [ -f "$index" ] && echo "$index"
      done
    done | sed -En "$regex" | sort -u
  )
  __yo_compgen "$subgens" "$cur"
  __yo_check_completed && __yo_finish_word
}

# @param $1 string  Current word to complete (cur)
# @param $2 integer  Index of the current word to complete (cword)
# @param ${@:3} array  Words typed so far (words)
# @stdout  Names of generators
_yo_gens() {
  local p index gens \
    IFS=$'\n' \
    cur=$1 \
    cword=$2 \
    words=( "${@:3}" ) \
    regex='s/.*generator-([^/\]+).*/\1/p'

  # only one generator allowed
  [ -n "$( __yo_first_arg "$cword" "${words[@]}" )" ] && return

  gens=$(
    echo 'doctor'  # technically, not a generator, but listed with them

    for p in $( __yo_node_path ); do
      for index in "$p"/generator-*/{,{,lib/}generators/}app/index.js; do
        [ -f "$index" ] && echo "$index"
      done
    done | sed -En "$regex" | sort -u
  )

  __yo_compgen "$gens" "$cur"

  if __yo_check_completed "$cur"; then
    case $cur in
      doctor) __yo_finish_word ;;
      *)      __yo_compgen "$cur:" "$cur"
    esac
  fi
}

# @param $1 string  Current word to complete (cur) or empty string
# @param $COMPREPLY global array  Generated completions
# @return  True (0) if only 1 completion present and, either current word
#          not supplied, or it matches the completion, False(>0) otherwise
__yo_check_completed() {
  if [[ ${#COMPREPLY[@]} -eq 1 && ( -z $1 || $1 == $COMPREPLY ) ]]; then
    return 0
  fi
  return 1
}

# @modifies $COMPREPLY global array  Generated completions
__yo_finish_word() {
  COMPREPLY=( "$COMPREPLY " )  # complete and move on
}

# @param $1 string  Potential completions
# @param $2 string  Current word to complete (cur)
# @modifies $COMPREPLY global array  Generated completions
__yo_compgen() {
  COMPREPLY=( $( compgen -W "$1" -- "$2" ) )
}

_yo() {
  local cur= cword= words= \
    IFS=$' \t\n'

  __yo_get_comp_words

  case $cur in
    -*) _yo_opts    "$cur" "$cword" "${words[@]}" ;;
   *:*) _yo_subgens "$cur" "$cword" "${words[@]}" ;;
     *) _yo_gens    "$cur" "$cword" "${words[@]}"
  esac

  __yo_ltrim_colon_completions "$cur"

  return 0
}

complete -o nospace -o default -F _yo yo
