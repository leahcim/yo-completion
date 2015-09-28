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

  while [ $((--i)) -ge 0 ]; do
    item=${COMPREPLY[$i]}
    COMPREPLY[$i]=${item#$prefix}
  done
}

# @param $1 string  (Sub)generator name, in the format 'aa' or 'aa:bb'
# @stdout  Path to the generator named
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

# @param $1 string  Path to a generator
# @stdout  List of generator's options (flags)
__yo_gen_opts() {
  local index="$1/index.js" \
    regex="s/.*this\.\(option\|hookFor\)(.*\(['\"]\)\([^\2]\+\)\2.*/\3/p"

  [ -f "$index" ] && sed -n "$regex" "$index" | sort -u | sed 's/^/--/'
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
  local path i=$1 words=( ${*:2} )

  while [ $(( --i )) -ge 1 ]; do
    path="$( __yo_gen_path "${words[$i]}" )"
    [ -n "$path" ] && echo "$( __yo_gen_opts "$path" )" && return
  done
  echo $( __yo_main_opts )
}

# @stdout  Names of (sub)generators in the format 'aa' or 'aa:bb'
_yo_generators() {
  local IFS=$'\n' i \
    regex1='s/.*generator-//' \
    regex2='s|/generators||' \
    regex2='s|/index.js||'

  for i in $( __yo_node_path ); do
    ls -df "$i"/generator-*/{,generators/}*/index.js 2>/dev/null
  done | sed "$regex1;$regex2;$regex3" | sort -u | tr '/' ':'
}

# @param $1 string  Completions
# @param $2 string  Current word to complete (cur)
# @modifies global array $COMPREPLY
__yo_compgen() {
  COMPREPLY=( $(compgen -W "$1" -- "$2") )
  __yo_ltrim_colon_completions "$2"
}

_yo() {
  local cur prev cword words \
    exclude=':='  # don't divide words on these characters

  _get_comp_words_by_ref -n "$exclude" cur prev cword words

  case "$cur" in
  -*) __yo_compgen "$( _yo_opts "$cword" "${words[*]}" )" "$cur" ;;
   *) __yo_compgen "$( _yo_generators )" "$cur"
  esac

  return 0
}

complete -F _yo yo