#!/bin/sh

BIN=$(readlink "${0}")
if [ -z ${BIN} ]; then
    BIN=${0}
fi
PROJECT_ROOT=$(dirname $(dirname $(cd $(dirname "${BIN}"); pwd)))
SOURCE_ROOT=${PROJECT_ROOT}/src
ENV_ROOT=${PROJECT_ROOT}/env

${ENV_ROOT}/bin/python ${SOURCE_ROOT}/manage.py $@