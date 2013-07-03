#!/bin/sh
BINARY="manage.py"
VIRTUALENV_DIRECTORY="env"

SELF_DIR=$(readlink "${0}"); [ -z ${SELF_DIR} ] && SELF_DIR=${0}
SOURCE_ROOT=$(cd $(dirname "${SELF_DIR}"); pwd)
RESULT=false
RETVAL=0

while [ "${SOURCE_ROOT}" != "/" ] && ! $RESULT; do
    [ -f ${SOURCE_ROOT}/${BINARY} ] && RESULT=true
    ! $RESULT && SOURCE_ROOT=$(dirname "${SOURCE_ROOT}")
done

if $RESULT; then
    echo "Execute ${SOURCE_ROOT}/${BINARY}"
    PROJECT_ROOT=$(dirname "${SOURCE_ROOT}")
    ENV_ROOT=${PROJECT_ROOT}/${VIRTUALENV_DIRECTORY}
    
    ${ENV_ROOT}/bin/python ${SOURCE_ROOT}/${BINARY} $@
else
    echo "Error: ${BINARY} not found" >&2
    RETVAL=1
fi

exit $RETVAL