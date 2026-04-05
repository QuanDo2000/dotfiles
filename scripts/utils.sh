#!/bin/bash

info() {
  [[ "$QUIET" == "true" && "$2" != "--force" ]] && return
  printf '\r  [ \033[00;34m..\033[0m ] %s\n' "$1"
}

user() {
  printf '\r  [ \033[0;33m??\033[0m ] %b\n' "$1"
}

success() {
  [[ "$QUIET" == "true" && "$2" != "--force" ]] && return
  printf '\r\033[2K  [ \033[00;32mOK\033[0m ] %s\n' "$1"
}

fail() {
  printf '\r\033[2K  [\033[0;31mFAIL\033[0m] %s\n' "$1"
  echo ''
  exit 1
}

fail_soft() {
  printf '\r\033[2K  [\033[0;31mFAIL\033[0m] %s\n' "$1"
}
