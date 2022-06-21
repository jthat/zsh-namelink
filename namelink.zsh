#
# zsh plugin for managing sets of named directories
#
# Copyright © 2021-2022 Jason Thatcher.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#

zmodload zsh/datetime || { print "$0: unable to load zsh/datetime" >&2; return 1; }
zmodload -F zsh/stat b:zstat || { print "$0: unable to load zsh/stat" >&2; return 1; }
zmodload -F zsh/parameter p:nameddirs || { print "$0: unable to load zsh/parameter" >&2; return 1; }
autoload -Uz add-zsh-hook || { print "$0: unable to load add-zsh-hook" >&2; return 1; }

namelink_init() {
  declare -g -i namelink_conf_verbose=0
  declare -g -a namelink_conf_inputs=( var:namelink dir:~/.namelink )
  declare -g -a namelink_conf_outputs=( var:nameddirs dir:~/.@ )
  declare -g -i namelink_conf_precmd_enable=1
  declare -g -i namelink_conf_preexec_enable=1
  declare -g -i namelink_conf_stat_dirs=1
  declare -g -i namelink_conf_always_sync=0

  declare -g -F namelink_read_timestamp=0
  declare -g -F namelink_write_timestamp=0
  declare -g -i namelink_sync_inputs=1
  declare -g -i namelink_sync_outputs=1

  declare -g -A namelink_cache=()
  declare -g -A namelink=()

  readonly -g namelink_tilde='~'
}

namelink_run() {
  if (( $namelink_conf_verbose > 2 )) {
    { print -n "$0: "; pwd } >&2
    setopt localoptions xtrace
  }
  $@
}

namelink_sync_input_dir() {
  setopt local_options extended_glob
  local index=$1
  local dir=$2
  namelink_run builtin cd $dir 2>/dev/null || {
    (( $namelink_conf_verbose )) && { print "$0: skipping input directory: ${(D)dir}" >&2 }
    return
  }

  (( $namelink_conf_verbose )) && { print "$0: loading input directory: ${(D)dir}" >&2 }

  local -A map=()
  local e
  for e (*(DN)) {
    local dest=$e
    local -A e_info=()
    # if the entry is a symbolic link, resolve its value
    if zstat -L -H e_info $e 2>/dev/null && [[ -n $e_info[link] ]]; then
      dest=${e_info[link]}
    fi
    map[$e]=${dest:a}
  }

  local name=namelink_input_${index}
  declare -g -A ${name}
  : ${(AAP)name::=${(@kv)map}}
}

namelink_sync_input_var() {
  local index=$1
  local var=$2

  (( $namelink_conf_verbose )) && { print "$0: loading input variable: ${(D)var}" >&2 }

  local name=namelink_input_${index}
  declare -g -A ${name}
  : ${(AAP)name::=${(@kvP)var}}
}

namelink_sync_inputs() {
  namelink_read_timestamp=$EPOCHREALTIME
  local orig_pwd=${PWD}
  local i
  for (( i=1; i != (${#namelink_conf_inputs}+1); i=$i+1 )); do
    local input=(${(s.:.)namelink_conf_inputs[$i]})
    namelink_sync_input_${input[1]} $i ${input[2]}
  done
  namelink_run builtin cd $orig_pwd || {
    print "$0: error: unable to change to original working directory: ${orig_pwd}" >&2
  }
  namelink_sync_inputs=0
}

namelink_sync_output_dir() {
  setopt local_options extended_glob
  local index=$1
  local dir=$2
  namelink_run builtin cd $dir 2>/dev/null || {
    (( $namelink_conf_verbose )) && { print "$0: skipping output directory: ${(D)dir}" >&2 }
    return 1
  }

  (( $namelink_conf_verbose > 3 )) && { command ls -a >&2 }

  local synced=()
  local IFS=''

  local e
  for e (*(DN)) {
    local update=0

    local -A e_info=()
    zstat -L -H e_info $e 2>/dev/null || {
      print "$0: error: ${(D)dir}: unable to lstat: ${e}" >&2
      continue
    }

    if [[ -z $e_info[nlink] ]] {
      print "$0: warning: ignoring non-symlink ${e} in ${(D)dir}" >&2
      continue
    }

    [[ -v namelink_cache[$e] ]] || {
      (( $namelink_conf_verbose )) && { print "$0: ${(D)dir}: DELETE: ${e}" >&2 }
      namelink_run command \rm -f -- ${e} || {
        print "$0: error: unable to delete link in ${(D)dir}: ${e}" >&2
        continue
      }
      namelink_fschange=1
      continue
    }

    local v=$namelink_cache[$e]

    # if the link is already correct, skip it
    if [[ ${e_info[link]} = $v ]] {
      synced+=($e)
      (( $namelink_conf_verbose > 1 )) && { print "$0: ${(D)dir}: SKIP: ${e} -> ${v}" >&2 }
      continue
    }

    # the link is stale; update it
    (( $namelink_conf_verbose )) && { print "$0: ${(D)dir}: UPDATE: ${e} -> ${v}" >&2 }
    namelink_run command \ln -s -n -f -- ${v} ${e} || {
      print "$0: error: unable to update link in ${(D)dir}: ${e} -> ${v}" >&2
      continue
    }
    synced+=($e)
    namelink_fschange=1
  }

  # create the set of links that haven't yet been processed
  local orphans=(${${(@k)namelink_cache}:|synced})
  local o
  for o (${orphans}) {
    local v=$namelink_cache[$o]
    (( $namelink_conf_verbose )) && { print "$0: ${(D)dir}: CREATE: ${o} -> ${v}" >&2 }
    namelink_run command \ln -s -n -- ${v} ${o} || {
      print "$0: error: unable to create link in ${(D)dir}: ${o} -> ${v}" >&2
      continue
    }
    namelink_fschange=1
  }

  (( $namelink_conf_verbose > 3 )) && { command ls -a >&2 }
}

namelink_sync_output_var() {
  local index=$1
  local var=$2

  (( $namelink_conf_verbose )) && { print "$0: loading output variable: ${(D)var}" >&2 }

  local name=namelink_input_${index}
  declare -g -A ${var}
  : ${(AAP)var::=${(@kv)namelink_cache}}
}

namelink_sync_outputs() {
  namelink_write_timestamp=$EPOCHREALTIME
  local orig_pwd=${PWD}
  for (( i=1; i != (${#namelink_conf_outputs}+1); i=$i+1 )); do
    local output=(${(s.:.)namelink_conf_outputs[$i]})
    namelink_sync_output_${output[1]} $i ${output[2]}    
  done
  namelink_run builtin cd $orig_pwd || {
    print "$0: error: unable to change to original working directory: ${orig_pwd}" >&2
  }
  namelink_sync_outputs=0
}

namelink_sync() {
  case $1 in -f|--force) namelink_sync_inputs=1; shift;; esac

  (( $namelink_sync_inputs )) || (( $namelink_sync_outputs )) || return

  if (( $namelink_sync_inputs )) {
    (( $namelink_conf_verbose > 1 )) && { print "$0: input marked sync" >&2 }
    namelink_sync_inputs
  }

  (( $namelink_conf_verbose )) && { print "$0: rebuilding cache" >&2 }
  local i
  for (( i=1; i != (${#namelink_conf_inputs}+1); i=$i+1 )); do
    local name=namelink_input_${i}
    namelink_cache+=(${(@kvP)name})
  done
  local k= v= gsv= changed=1
  while (( $changed )) {
    changed=0
    for k v (${(@kv)namelink_cache}) {
      [[ $v[1] = $namelink_tilde ]] || continue
      # extract the identifier between '~' and an optional '/'
      local ref=${${v%%/*}[$((${#namelink_tilde}+1)),-1]}
      local val=
      if [[ -z $ref ]] {
        val=$HOME
      } else {
        val=$namelink_cache[$ref]
      } 
      if [[ -n $val ]] {
        # replace the reference with its resolved value
        namelink_cache[$k]=${val}${v[$((${#namelink_tilde}+${#ref}+1)),-1]}
        changed=1
      }
    }
  }

  (( $namelink_conf_verbose > 1 )) && { print "$0: output marked sync" >&2 }
  declare -g -i namelink_fschange=0
  namelink_sync_outputs
  if (( $namelink_fschange )) {
    namelink_sync_outputs
  }
  unset namelink_fschange
}

namelink_stat_dirs() {
  local i d

  (( $namelink_sync_inputs )) || {
    for (( i=1; i != (${#namelink_conf_inputs}+1); i=$i+1 )); do
      local input=(${(s.:.)namelink_conf_inputs[$i]})
      [[ $input[1] = dir ]] || continue
      d=$input[2]
      local -A s=()
      zstat -F '%s.%9.' -H s $d 2>/dev/null || continue
      if (( $namelink_read_timestamp < $s[mtime] )) {
        (( $namelink_conf_verbose )) && { print "$0: mtime trigger on input dir ${(D)d}" >&2 }
        namelink_sync_inputs=1
        break
      }
    done
  }

  (( $namelink_sync_inputs )) && namelink_sync_outputs=1

  (( $namelink_sync_outputs )) || {
    for (( i=1; i != (${#namelink_conf_outputs}+1); i=$i+1 )); do
      local output=(${(s.:.)namelink_conf_outputs[$i]})
      [[ $output[1] = dir ]] || continue
      d=$output[2]
      local -A s=()
      zstat -F '%s.%9.' -H s $d 2>/dev/null || continue
      if (( $namelink_write_timestamp < $s[mtime] )) {
        (( $namelink_conf_verbose )) && { print "$0: mtime trigger on output dir ${(D)d}" >&2 }
        namelink_sync_outputs=1
        break
      }
    done
  }
}

namelink_setopt() {
  local name=$1
  shift

  local var=namelink_conf_${name}

  case $name in
    inputs|outputs)
      : ${(AP)var::=${(A)@}}
      local dvar=namelink_sync_${name}
      : ${(P)dvar::=1}
      (( $namelink_conf_always_sync )) && namelink_sync
      return
      ;;
  esac

  [[ -v $var ]] || {
    print "$0: error: unknown option: ${name}" >&2
    return 1
  }

  [[ ${(P)var} == $1 ]] && return

  : ${(P)var::=$1}
}

namelink_getopt() {
  local quiet=0; case $1 in -q|--quiet) quiet=1; shift;; esac

  local name=$1
  shift

  local var=namelink_conf_${name}

  declare -g -a reply=(${(P)var})
  (( $quiet )) || print ${(j.:.)reply}
}

namelink_load() {
  namelink_load_internal() {
    namelink[$1]=$2
    namelink_sync_outputs=1
    return 0
  }

  if (( $# )) {
    while (( $# )) {
      namelink_load_internal $1 $2
      shift 2
    }
  } else {
    local IFS=''
    while read -A; do
      local line=$reply[1]
      [[ $line =~ '^[[:space:]]*(#.*)?$' ]] && continue
      [[ $line =~ '^([^[:space:]]+)[[:space:]]+(.*)$' ]] || continue
      namelink_load_internal $match
    done
  }

  unfunction namelink_load_internal
  (( $namelink_conf_always_sync )) && namelink_sync
  return 0
}

namelink_unload() {
  if [[ $1 = -a ]] {
    (( ${#namelink} == 0 )) && return 0
    namelink=()
    namelink_sync_outputs=1
    (( $namelink_conf_always_sync )) && namelink_sync
    return 0
  }

  namelink_unload_internal() {
    [[ -v namelink[$1] ]] || return 0
    local k v
    for k v (${(@kv)namelink}) {
      [[ $v[1] = $namelink_tilde ]] || continue
      # extract the identifier between '~' and an optional '/'
      local ref=${${v%%/*}[$((${#namelink_tilde}+1)),-1]}
      if [[ $ref = $1 ]] {
        # replace the reference with its resolved value
        namelink[$k]=${namelink[$1]}${v[$((${#namelink_tilde}+${#ref}+1)),-1]}
      }
    }
    unset "namelink[$1]"
    namelink_sync_outputs=1
  }

  if (( $# )) {
    while (( $# )) {
      namelink_unload_internal $1
      shift
    }
  } else {
    local IFS=''
    while read -A; do
      local line=$reply[1]
      [[ $line =~ '^[[:space:]]*(#.*)?$' ]] && continue
      [[ $line =~ '^([^[:space:]]+)([[:space:]]+(.*))?$' ]] || continue
      namelink_unload_internal ${match[1]}
    done
  }

  unfunction namelink_unload_internal
  (( $namelink_conf_always_sync )) && namelink_sync
  return 0
}

namelink_show() {
  local k=
  local -A m=(${(@kv)namelink})
  (( $# == 0 )) && set -- ${(@ko)m}
  for k; do
    [[ -v m[$k] ]] || continue
    print "${k} ${m[$k]}"
  done
}

namelink_precmd_hook() {
  (( $namelink_conf_precmd_enable )) || return 0
  (( $namelink_conf_verbose > 5 )) && { print "$0" >&2 }
  (( $namelink_conf_stat_dirs )) && namelink_stat_dirs
  namelink_sync
}

namelink_preexec_hook() {
  (( $namelink_conf_preexec_enable )) || return 0
  (( $namelink_conf_verbose > 5 )) && { print "$0" >&2 }
  (( $namelink_conf_stat_dirs )) && namelink_stat_dirs
  namelink_sync
}

namelink() {
  if (( $# == 0 )) {
    print "$0: missing action" >&2
    return 1
  }

  local fun=$1
  shift

  [[ $(builtin whence -w namelink_${fun}) =~ '[[:space:]]function$' ]] || {
    print "$0: unknown action: ${fun}" >&2
    return 1
  }

  namelink_${fun} $@
}

add-zsh-hook precmd namelink_precmd_hook
add-zsh-hook preexec namelink_preexec_hook

namelink_init
