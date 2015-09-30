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

# Remove word-colon prefix from COMPREPLY items
# @param $1 string  Current word to complete (cur)
# @param $COMPREPLY global array  Completions prefixed with '<GENERATOR>:'
# @modifies global array $COMPREPLY
__yo_ltrim_colon_completions() {
  local item prefix \
    cur="$1" \
    i=${#COMPREPLY[*]}

  prefix=${cur%${cur##*:}}

  while [ $(( --i )) -ge 0 ]; do
    item=${COMPREPLY[$i]}
    COMPREPLY[$i]=${item#$prefix}
  done
}

# @param $1 string  Path containing instances of /../ or /./
# @stdout  Normalised path
__yo_collapse_path() {
  local basename dirname="${1%[/\\]*}"
  basename="${1#$dirname}"  # '/a/b' -> '/b', 'C:\a\b' -> '\b'

  [ -d "$dirname" ] && echo "$(cd "$dirname"; pwd)${basename}"
}

# @param $1 string  (Sub)generator name, in the format 'aa' or 'aa:bb'
# @stdout  Path to the (sub)generator named
__yo_gen_path() {
  local IFS=$'\n' gen subgen p

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
  local files file path IFS=$'\n' \
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
  local paths required IFS=$'\n' \
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
# @param $2 string  Words typed so far (words)
# @stdout  Options (flags) for the main command or for a (sub)generator
_yo_opts() {
  local path=$( __yo_first_gen "$1" "${*:2}" )

  [ -n "$path" ] && echo "$( __yo_gen_opts "$path" )" && return
  echo $( __yo_main_opts )
}

# @param $1 integer  Index of the current word to complete (cword)
# @param $2 string  Words typed so far (words)
# @stdout  Path to the 1st (sub)generator on the command line, if specified
# @return  True (0) if (sub)generator found, False (>0) otherwise
__yo_first_gen() {
  local path words i=0 IFS=' '
  words=( ${*:2} )

  while [ $(( ++i )) -lt $1 ]; do
    path="$( __yo_gen_path "${words[$i]}" )"
    [ -n "$path" ] && echo "$path" && return 0
  done

  return 1
}

# @param $1 integer  Index of the current word to complete (cword)
# @param $2 string  Words typed so far (words)
# @stdout  Names of (sub)generators in the format 'aa' or 'aa:bb'
_yo_generators() {
  local IFS=$'\n' i \
    regex1='s/.*generator-//' \
    regex2='s|/generators||' \
    regex2='s|/index.js||'

  # Only one generator allowed
  ( __yo_first_gen "$1" "${*:2}" > /dev/null ) && return

  for i in $( __yo_node_path ); do
    ls -df "$i"/generator-*/{,generators/}*/index.js 2> /dev/null
  done | sed "$regex1;$regex2;$regex3" | sort -u | tr '/' ':'
}

# @param $1 string  Completions
# @param $2 string  Current word to complete (cur)
# @modifies global array $COMPREPLY
__yo_compgen() {
  COMPREPLY=( $( compgen -W "$1" -- "$2" ) )
  __yo_ltrim_colon_completions "$2"
}

_yo() {
  local cur prev cword words \
    IFS=$' \t\n' \
    exclude=':='  # don't divide words on these characters

  _get_comp_words_by_ref -n "$exclude" cur prev cword words

  case "$cur" in
  -*) __yo_compgen "$( _yo_opts "$cword" "${words[*]}" )" "$cur" ;;
   *) __yo_compgen "$( _yo_generators "$cword" "${words[*]}" )" "$cur"
  esac

  return 0
}

complete -F _yo yo
