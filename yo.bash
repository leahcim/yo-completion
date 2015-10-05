# Command completion for Yeoman
# by Michael Ichnowski

# Default value for $NODE_PATH - a one-off performance penalty only
# incurred if $NODE_PATH has not been set
: ${NODE_PATH:=$( npm -g root )}

# @param $OSTYPE global string  System variable
# @param $NODE_PATH global string  Node.js variable with module locations
# @param $PWD global string  Current location in file system
# @stdout  List of Node.js module locations
__yo_node_path() {
  local IFS p

  case $OSTYPE in
    *cygwin*|*msys*) IFS=';' ;; # Windows
    *)               IFS=':' ;; # Unix
  esac

  for p in $NODE_PATH; do echo "$p"; done
  echo "$PWD/node_modules"  # faster than calling $(npm root)
}

# @param $1 integer  Max # of lines to read from each file (default: 1000)
# @stdin  New-line separated list of file paths to read from
# @stdout  Concatenated contents of all files specified that exist
__yo_cat() {
  local file_name line i

  while read -r file_name; do
    [ -f "$file_name" ] || continue
    [ -n "$1" ] && i=$1 || i=1000  # max. no. of lines to read
    while read -r line && (( i-- > 0 )); do
      echo "$line"
    done < "$file_name"
  done
}

# @param $1 string  Regular expresion to match
# @param $2 string  Replacement pattern referencing matched groups: \0-\9
# @param $BASH_REMATCH global array  Matched subexpressions (groups)
# @stdin  Lines of input to match and modify
# @stdout  Lines matching regex ($1) modified according to $2
__yo_sed() {
  local line regex=$1 output=$2

  while [[ $output =~ (.*)\\([0-9])(.*) ]]; do
    output="${BASH_REMATCH[1]}"
    output+="\${BASH_REMATCH[${BASH_REMATCH[2]}]}"
    output+="${BASH_REMATCH[3]}"
  done

  while read -r line; do
    [[ $line =~ $regex ]] && eval "echo $output"
  done
}

# Assign value to variable referenced by $1, but only if it's been set
# @param $1 string  Name of a variable to assign to
# @param $2 primitive  String/integer value to assign to the variable
# @modifies ${!1}  Variable referenced indirectly by $1, if set
__yo_up_var() {
  [ -n "${!1+set}" ] && eval "$1='$2'"
}

# Assign array to variable referenced by $1, but only if it's been set
# @param $1 string  Name of a variable to assign to
# @param $2 array  Array values to assign to the variable
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
    prev_char=${COMP_LINE:$(( COMP_POINT -1 )):1}

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
# @modifies $COMPREPLY global array
__yo_ltrim_colon_completions() {
  local item prefix \
    cur="$1" \
    i=${#COMPREPLY[@]}

  prefix=${cur%${cur##*:}}
  [ -z "$prefix" ] && return

  while [ $(( --i )) -ge 0 ]; do
    item=${COMPREPLY[$i]}
    COMPREPLY[$i]=${item#$prefix}
  done
}

# @param $1 string  Path containing instances of /../ or /./
# @stdout  Normalised path
__yo_collapse_path() {
  local basename \
    dirname="${1%[/\\]*}"

  basename="${1#${dirname//\\/\\\\}}"  # '/a/b' -> '/b', 'C:\a\b' -> '\b'

  [ -d "$dirname" ] && echo "$(cd "$dirname"; pwd)${basename}"
}

# @param $1 string  (Sub)generator name, in the format 'aa' or 'aa:bb'
# @stdout  Path to the (sub)generator named
__yo_gen_path() {
  local gen subgen p \
    IFS=$'\n'

  gen=${1%:*}              # 'aa:bb' -> 'aa', 'aa' -> 'aa'
  if [[ $1 == *:* ]]; then
    subgen=${1#*:}         # 'aa:bb' -> 'bb'
  else
    subgen='app'           # set default value
  fi

  for p in $( __yo_node_path ); do
    if [ -f "$p/generator-$gen/$subgen/index.js" ]; then
       echo "$p/generator-$gen/$subgen"
       return
    elif [ -f "$p/generator-$gen/generators/$subgen/index.js" ]; then
       echo "$p/generator-$gen/generators/$subgen"
       return
    fi
  done
}

# @param $1 string  List of newline-delimited paths to *.js files
# @stdout  List of paths to files required by files given
__yo_gen_required() {
  local files file path \
    IFS=$'\n' \
    regex="require\(\s*(['\"])(\.[^'\"]+)\1" output='\2'

  for path in $1; do
    [ -f "$path" ] || continue

    # don't search whole files - prioritise speed
    files=$(echo "$path" | __yo_cat 15 | __yo_sed "$regex" "$output")

    path="${path%${path##*[/\\]}}"  # '/a/b' -> '/a/', 'C:\a\b' -> 'C:\a\'

    for file in $files; do

      file="${path}${file}"
      [ -f "$file" ] &&
        echo "$( __yo_collapse_path "$file" )" && continue

      file+='.js'
      [ -f "$file" ] &&
        echo "$( __yo_collapse_path "$file" )"

    done
  done | sort -u
}

# @param $1 string  Path to a (sub)generator
# @stdout  List of (sub)generator's options (flags)
__yo_gen_opts() {
  local required \
    index="$1/index.js" \
    regex="\.(option|hookFor)\(\s*(['\"])([^'\"]+)\2" output='--\3'

  if [ -f "$index" ]; then
    echo '--help'
    {
      echo "$index"

      required="$( __yo_gen_required "$index" )"$'\n'
      required+="$( __yo_gen_required "$required" )"
      echo "$required"

    } | sort -u | __yo_cat | __yo_sed "$regex" "$output"
  fi | sort -u
}

# @stdout  Main command options (flags)
__yo_main_opts() {
  echo '
    --force --generators --help --insight
    --no-color --no-insight --version'
}

# @param $1 integer  Index of the current word to complete (cword)
# @param ${@:2} array  Words typed so far (words)
# @stdout  Options (flags) for the main command or for a (sub)generator
_yo_opts() {
  local path opts \
    cword=$1 \
    words=( "${@:2}" )

  path=$( __yo_first_gen "$cword" "${words[@]}" )

  if [ -n "$path" ]; then
    opts="$( __yo_gen_opts "$path" )"
  else
    opts=$( __yo_main_opts )
  fi
  __yo_compgen "$opts" "${words[$cword]}"
  __yo_check_completed "${words[$cword]}" && __yo_finish_word
}

# @param $1 integer  Index of the current word to complete (cword)
# @param ${@:2} array  Words typed so far (words)
# @stdout  Path to the 1st (sub)generator on the command line, if specified
# @return  True (0) if (sub)generator found, False (>0) otherwise
__yo_first_gen() {
  local path i=0 \
    words=( "${@:2}" )

  while [ $(( ++i )) -lt $1 ]; do
    path="$( __yo_gen_path "${words[$i]}" )"
    [ -n "$path" ] && echo "$path" && return 0
  done

  return 1
}

# @param $1 integer  Index of the current word to complete (cword)
# @param ${@:2} array  Words typed so far (words)
# @stdout  Names of sub-generators in the format 'aa:bb'
_yo_subgens() {
  local p subgens \
    IFS=$'\n' \
    cword=$1 \
    words=( "${@:2}" ) \
    regex='generator-([^/\\]+)[/\\]' \
    regex+='(generators[/\\]|)' \
    regex+='([^/\\]+)[/\\]index\.js' output='\1:\3'

  # only one generator allowed
  ( __yo_first_gen "$cword" "${words[@]}" > /dev/null ) && return

  subgens=$(
    for p in $( __yo_node_path ); do
      ls -df "$p"/generator-*/{,generators/}*/index.js 2> /dev/null
    done | __yo_sed "$regex" "$output" | sort -u
  )
  __yo_compgen "$subgens" "${words[$cword]}"
  __yo_check_completed && __yo_finish_word
}

# @param $1 integer  Index of the current word to complete (cword)
# @param ${@:2} array  Words typed so far (words)
# @stdout  Names of generators
_yo_gens() {
  local p gens \
    IFS=$'\n' \
    cword=$1 \
    words=( "${@:2}" ) \
    regex='generator-([^/\\]+)' output='\1'

  # only one generator allowed
  ( __yo_first_gen "$cword" "${words[@]}" > /dev/null ) && return

  gens=$(
    for p in $( __yo_node_path ); do
      ls -df "$p"/generator-*/{,generators/}app/index.js 2> /dev/null
    done | __yo_sed "$regex" "$output" | sort -u
  )
  __yo_compgen "$gens" "${words[$cword]}"
  if __yo_check_completed "${words[$cword]}"; then
   _yo_subgens "$cword" "${words[@]}"
  fi
}

# @param $1 string  Current word to complete (cur) or empty string
# @param $COMPREPLY global array  Completions
# @return  True (0) if unique completion matches current word, if given,
#          False(>0), otherwise
__yo_check_completed() {
  if [[ ${#COMPREPLY[@]} -eq 1 && ( -z $1 || $1 == $COMPREPLY ) ]]; then
    return 0
  fi
  return 1
}

# @modifies $COMPREPLY global array
__yo_finish_word() {
  COMPREPLY=( "$COMPREPLY " )  # complete and move on
}

# @param $1 string  Completions
# @param $2 string  Current word to complete (cur)
# @modifies $COMPREPLY global array
__yo_compgen() {
  COMPREPLY=( $( compgen -W "$1" -- "$2" ) )
}

_yo() {
  local cur= cword= words= \
    IFS=$' \t\n'

  __yo_get_comp_words

  case "$cur" in
    -*) _yo_opts    "$cword" "${words[@]}" ;;
   *:*) _yo_subgens "$cword" "${words[@]}" ;;
     *) _yo_gens    "$cword" "${words[@]}"
  esac

  __yo_ltrim_colon_completions "$cur"

  return 0
}

complete -o nospace -o default -F _yo yo
