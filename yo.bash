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

# @param $1 string  Characters which should not count as word breaks
# @param $COMP_WORDBREAKS global string  Characters used as word breaks
# @param $COMP_CWORD  Index of the current (partial) word
# @param $COMP_WORDS global array  (Partial) words entered so far
# @modifies $cur string  Current word to complete
# @modifies $cword integer  Index of the current word
# @modifies $words array  Words typed so far
__yo_get_comp_words() {
  local i j item exclude ahead _cur _cword _words \
    appending='true'

  # Only keep characters actually listed as word breaks
  exclude=${1//[^$COMP_WORDBREAKS]}

  _words=( $COMP_WORDS )  # start off with the first word (the command)
  for (( i=1, j=1; i < ${#COMP_WORDS[@]}; i++ )); do

    item="${COMP_WORDS[i]}"
    case $item in
      [$exclude])
        _words[j]+=$item
        appending='true' ;;
      *)
        [ "$appending" == 'false' ] && (( j++ ))
        _words[j]+=$item
        appending='false'
    esac

    [ $i -eq $COMP_CWORD ] && _cword=$j
  done

  # find part of current word ahead of the cursor
  ahead=${COMP_LINE:$COMP_POINT}
  ahead=${ahead# }     # for when cursor is just before current word
  ahead=${ahead%% *}

  # trim part of current word ahead of the cursor
  _cur=${_words[$_cword]%$ahead}

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
    regex="s/.*require(\s*\(['\"]\)\(\.[^'\"]\+\)\1.*/\2/p"

  for path in $1; do
    [ -f "$path" ] || continue

    # don't search whole files - prioritise speed
    files="$( head -n15 "$path" | sed -n "$regex" )"

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
  local paths required \
    IFS=$'\n' \
    index="$1/index.js" \
    regex="s/.*\.\(option\|hookFor\)(\s*\(['\"]\)\([^'\"]\+\)\2.*/\3/p"

  if [ -f "$index" ]; then
    echo 'help'

    paths=$({
      echo "$index"

      required="$( __yo_gen_required "$index" )"$'\n'
      required+="$( __yo_gen_required "$required" )"
      echo "$required"
    } | sort -u)

    sed -n "$regex" $paths 2> /dev/null
  fi | sort -u | sed 's/^/--/'
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
  local path=$( __yo_first_gen "$1" "${@:2}" )

  [ -n "$path" ] && echo "$( __yo_gen_opts "$path" )" && return
  echo $( __yo_main_opts )
}

# @param $1 integer  Index of the current word to complete (cword)
# @param ${@:2} array  Words typed so far (words)
# @stdout  Path to the 1st (sub)generator on the command line, if specified
# @return  True (0) if (sub)generator found, False (>0) otherwise
__yo_first_gen() {
  local path words i=0 IFS=' '
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
  local i \
    IFS=$'\n' \
    cword=$1 \
    words=( "${@:2}" ) \
    regex1='s/.*generator-//' \
    regex2='s|/generators||' \
    regex2='s|/index.js||'

  # only one generator allowed
  ( __yo_first_gen "$cword" "${words[@]}" > /dev/null ) && return

  for i in $( __yo_node_path ); do
    ls -df "$i"/generator-*/{,generators/}*/index.js 2> /dev/null
  done | sed "$regex1;$regex2;$regex3" | sort -u | tr '/' ':'
}

# @param $1 integer  Index of the current word to complete (cword)
# @param ${@:2} array  Words typed so far (words)
# @stdout  Names of generators
_yo_gens() {
  local i \
    IFS=$'\n' \
    cword=$1 \
    words=( "${@:2}" ) \
    regex='s/.*generator-\([^/\\]\+\).*/\1/p'

  # only one generator allowed
  ( __yo_first_gen "$cword" "${words[@]}" > /dev/null ) && return

  for i in $( __yo_node_path ); do
    ls -df "$i"/generator-*/{,generators/}app/index.js 2> /dev/null
  done | sed -n "$regex" | sort -u
}

# @param $1 string  Completions
# @param $2 string  Current word to complete (cur)
# @modifies $COMPREPLY global array
__yo_compgen() {
  COMPREPLY=( $( compgen -W "$1" -- "$2" ) )
}

_yo() {
  local cur= cword= words= i=0 \
    IFS=$' \t\n' \
    exclude=':='  # don't divide words on these characters

  __yo_get_comp_words "$exclude"

  case "$cur" in
    -*) __yo_compgen "$( _yo_opts    "$cword" "${words[@]}" )" "$cur" ;;
   *:*) __yo_compgen "$( _yo_subgens "$cword" "${words[@]}" )" "$cur" ;;
     *) __yo_compgen "$( _yo_gens    "$cword" "${words[@]}" )" "$cur" ;;
  esac

  while [ ${#COMPREPLY[*]} -eq 1 ] && [ $(( ++i )) -le 2 ]; do
    case "$COMPREPLY" in
      [^-]*:*)
        COMPREPLY=( "$COMPREPLY " )  # Accept completion, move on
        break ;;
      $cur)
         # If option alrady complete, move on
        [[ $cur == -* ]] && COMPREPLY=( "$COMPREPLY " ) && break

        __yo_compgen "$( _yo_subgens "$cword" "${words[@]}" )" "$cur" ;;
    esac
  done

  __yo_ltrim_colon_completions "$cur"

  return 0
}

complete -o nospace -o default -F _yo yo
