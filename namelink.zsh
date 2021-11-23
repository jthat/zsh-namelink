#
# zsh plugin for synchronized mapping of filesystem entries to the named directory hash
#
# Copyright (C) 2021 Jason Thatcher.
# Licensed under the MIT license.
# SPDX-License-Identifier: MIT
#

zmodload zsh/datetime || { print "can't load zsh/datetime"; return }
zmodload -F zsh/stat b:zstat || { print "can't load zsh/stat"; return }
autoload -Uz add-zsh-hook || { print "can't load add-zsh-hook"; return }

namelink_timestamp=0
(( ${+namelink_path} )) || namelink_path=(~/.@)

namelink_hashdir() {
  setopt local_options extended_glob
  local d e
  for d; do
    for e ($d/*(N))
      hash -d ${e:t}=${e:P}
  done 2>/dev/null
}

namelink_rehash() {
  namelink_timestamp=$EPOCHREALTIME
  hash -d -r
  namelink_hashdir $namelink_path
}

namelink_rehash_quick() {
  local d
  local -A s

  for d ($namelink_path) {
    zstat -F '%s.%9.' -H s $d 2>/dev/null || continue
    if (( $namelink_timestamp < $s[mtime] )) {
      namelink_rehash
      return
    }
  }
}

namelink_setpath() {
  namelink_path=($@)
  namelink_rehash
}

add-zsh-hook precmd namelink_rehash_quick
add-zsh-hook preexec namelink_rehash_quick

namelink_rehash
