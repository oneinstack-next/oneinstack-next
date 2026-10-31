#!/bin/bash
# Remove only an allocated private directory beneath its declared parent.
# Resolve both paths before recursive cleanup; never follow a replaced root.
Prepare_Private_Dir() {
  local target=$1
  [ ! -L "$target" ] || return 1
  if [ ! -d "$target" ]; then (umask 077; mkdir -p -- "$target") || return 1; fi
  [ ! -L "$target" ] && [ "$(stat -c %u "$target")" = "$(id -u)" ] || return 1
  chmod 700 -- "$target"
}

Remove_Private_Tree() {
  local target=$1 parent=$2 resolved_target resolved_parent
  [ -e "$target" ] || [ -L "$target" ] || return 0
  [ -d "$target" ] && [ ! -L "$target" ] || return 1
  resolved_target=$(readlink -f -- "$target") || return 1
  resolved_parent=$(readlink -f -- "$parent") || return 1
  [[ $resolved_target == "$resolved_parent/"* && $resolved_target != "$resolved_parent" ]] || {
    echo 'Refusing cleanup outside the private staging parent' >&2; return 1;
  }
  rm -rf -- "$resolved_target"
}

Remove_Private_File() {
  local target=$1 parent=$2 actual_parent expected_parent
  [ -e "$target" ] || [ -L "$target" ] || return 0
  actual_parent=$(readlink -f -- "$(dirname -- "$target")") || return 1
  expected_parent=$(readlink -f -- "$parent") || return 1
  [ "$actual_parent" = "$expected_parent" ] && [ ! -d "$target" ] || return 1
  rm -f -- "$target"
}
