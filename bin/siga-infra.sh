#!/bin/bash

BASE_STACKS_FOLDER="$(dirname --  "$(dirname -- "$(pwd)/$0")")"
CONFIG_FILE="$BASE_STACKS_FOLDER/bin/siga-infra.conf"

if command -v docker >/dev/null 2>&1; then
  if ! docker stack ls >/dev/null 2>&1; then
    echo -n "Para utilizar esse script, o docker deve estar executando em modo swarm."
    exit 1
  fi
else
  echo -n "O comando docker não foi encontrado"
  exit 1
fi

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

if [ -z "$SIGA_SERVICE_POSTFIX" ]; then
  SIGA_SERVICE_POSTFIX="default"
fi

STACKS=""
add_stack_file() {
  if [[ "$1" != /* ]]; then
    STACK_FILE="$(pwd)/$1"
  else
    STACK_FILE=$1
  fi

  echo "$STACK_FILE"
  if [ -f "$STACK_FILE" ]; then
    STACKS="$STACKS -c $STACK_FILE"
  fi
}

check_binds() {
  base_path="$BASE_STACKS_FOLDER/data"

  if [ ! -d "$base_path/siga-$SIGA_SERVICE_POSTFIX" ]; then
    cp -r "$base_path/base" "$base_path/siga-$SIGA_SERVICE_POSTFIX"
  fi
}

deploy_siga() {
#  if [ -n "$(docker service ls -q -f "label=siga-$SIGA_SERVICE_POSTFIX")" ]; then
#    echo "O serviço do siga-$SIGA_SERVICE_POSTFIX já existe!. Por favor redefina a variável SIGA_SERVICE_POSTFIX"
#    exit
#  fi

  add_stack_file "$BASE_STACKS_FOLDER/siga-base.yaml"
  TLS=""

  ENTRY="web"
  while true; do
    case "$1" in
    --tls)
      shift
      if [ -z "${SIGA_HOST}" ];
      then
          echo "Para utilizar o siga em produção informe um valor para SIGA_HOST."
          exit 1
      fi
      TLS="true"
      ENTRY="websecure"
      ;;
    --test)
      shift
      add_stack_file "$BASE_STACKS_FOLDER/siga-homo.yaml"
      ;;
    --dev)
      shift
      add_stack_file "$BASE_STACKS_FOLDER/siga-homo.yaml"
      add_stack_file "$BASE_STACKS_FOLDER/siga-dev.yaml"
      ;;
    --alternative-entry)
      shift
      ENTRY="test"
      ;;
    --add)
      add_stack_file "$2"
      shift 2;
      ;;
    *) break ;;
    esac
  done

  if [ -n "$TLS" ]; then
    add_stack_file "$BASE_STACKS_FOLDER/siga-tls.yaml"
  fi

  check_binds
  eval "SIGA_HOST=$SIGA_HOST SIGA_SERVICE_POSTFIX=$SIGA_SERVICE_POSTFIX ENTRY=$ENTRY docker stack deploy$STACKS siga-${SIGA_SERVICE_POSTFIX-default}"
}

deploy_traefik() {
  add_stack_file "$BASE_STACKS_FOLDER/traefik-base.yaml"
  TLS=""

  while true; do
    case "$1" in
    --tls)
      shift
      if [ -z "${TRAEFIK_ACME_EMAIL}" ];
      then
          echo "Para utilizar o traefik com tls informe um valor para TRAEFIK_ACME_EMAIL."
          exit 1
      fi
      if [ -z "${TRAEFIK_HOST}" ];
      then
          echo "Para utilizar o traefik com tls informe um valor para TRAEFIK_HOST."
          exit 1
      fi
      TLS="true"
      break
      ;;
    *) break ;;
    esac
  done

  if [ -n "$TLS" ]; then
    add_stack_file "$BASE_STACKS_FOLDER/traefik-tls.yaml"
  else
     add_stack_file "$BASE_STACKS_FOLDER/traefik-default.yaml"
  fi

  eval "TRAEFIK_ACME_EMAIL=$TRAEFIK_ACME_EMAIL TRAEFIK_AUTH=$TRAEFIK_AUTH TRAEFIK_HOST=$TRAEFIK_HOST docker stack deploy$STACKS traefik"
}

deploy_swarmpit() {
  add_stack_file "$BASE_STACKS_FOLDER/swarmpit.yaml"

  eval "docker stack deploy$STACKS swarmpit"
}

deploy_command() {
  if ! docker network inspect traefik-public >/dev/null 2>&1; then
    docker network create --driver=overlay traefik-public
  fi

  case "$1" in
  traefik)
    shift
    eval "deploy_traefik $*"
    ;;
  siga)
    shift
    eval "deploy_siga $*"
    ;;
  swarmpit)
    shift
    eval "deploy_swarmpit $*"
    ;;
  esac
}

case "$1" in
deploy)
  shift
  eval "deploy_command $*"
  ;;
esac