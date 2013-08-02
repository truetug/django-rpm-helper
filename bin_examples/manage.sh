#!/bin/sh
NAME="superprogramm"
SEARCH_FILE="manage.py"
BINARY="python"
OPTS=""
VIRTUALENV_DIRECTORY="env"

SELF_DIR=$(readlink "${0}"); [ -z ${SELF_DIR} ] && SELF_DIR=${0}
SOURCE_ROOT=$(cd $(dirname "${SELF_DIR}"); pwd)
RESULT=false
RETVAL=0

while [ "${SOURCE_ROOT}" != "/" ] && ! $RESULT; do
    [ -f ${SOURCE_ROOT}/${SEARCH_FILE} ] && RESULT=true
    ! $RESULT && SOURCE_ROOT=$(dirname "${SOURCE_ROOT}")
done

if $RESULT; then
    PROJECT_ROOT=$(dirname "${SOURCE_ROOT}")
    ENV_ROOT=${PROJECT_ROOT}/${VIRTUALENV_DIRECTORY}
    #echo "Execute: cd ${SOURCE_ROOT} && exec ${ENV_ROOT}/bin/${BINARY} ${OPTS} $@"
    (cd ${SOURCE_ROOT} && exec ${ENV_ROOT}/bin/${BINARY} ${OPTS} $@)
    RETVAL=$?
else
    echo "Error: ${SEARCH_FILE} not found" 1>&2
    RETVAL=1
fi

exit $RETVAL