#!/bin/sh
# .../<anyprojectname>
#       /env - virtualenv
#       /src - source with manage.py
#       /packages - pip2pi


# settings
IS_PURGE=true # Clean RPM directory before build
IS_QUIET=false # rpmbuild with --quite option
PYPI="http://pypi.mail.ru/simple" # pypi index-url
BUILD_REQUIREMENTS=(python python-devel libjpeg libpng zlib freetype librabbitmq librabbitmq-devel mysql mysql-server mysql-devel) # build requirements


# predifined
BIN=$(readlink "${0}")
if [ -z ${BIN} ]; then
    BIN=${0}
fi
PROJECT_ROOT=$(dirname $(cd $(dirname "${BIN}"); pwd))
SOURCE_ROOT=${PROJECT_ROOT}/src

PACKAGES_ROOT=${PROJECT_ROOT}/packages
ENV_ROOT=${PROJECT_ROOT}/env
CUSTOM_COMMANDS=(setup_env setup_rpm build_rpm)

if [ -z ${PYPI} ]; then
    PYPI="http://pypi.python.org/simple"
fi

RETVAL=0


# functions
command_exists() {
    command -v "$1" > /dev/null 2>&1
}

programm_exists() {
    if ! command_exists rpm; then
        echo "This program only for RPM based distributives"
        exit 1
    fi
    rpm -qa | grep $1 > /dev/null 2>&1
}

list_check() {
    func=${1}
    shift
    to_check=${@}

    IS_OK=true
    TO_INSTALL=()
    for prog in ${to_check}; do
        cmd="${func} ${prog}"
        echo -n "Checking for ${prog}... "
        if ! eval ${cmd}; then
            IS_OK=false
            TO_INSTALL+=("${prog}")
            echo "FAIL"
        else
            echo "OK"
        fi
    done

    if ! $IS_OK; then
        echo "Install: ${REQUIREMENTS[@]}"
        exit
    fi
}

func_setup_env() {
    # Create virtualenv if not exists
    if [ ! -f ${ENV_ROOT}/bin/python ] ; then
        echo "Creating virtualenv... "
        virtualenv --distribute ${ENV_ROOT}
    fi

    # Update requirements
    if [ ! -d ${PACKAGES_ROOT} ]; then
        echo "Install requirements... "
        func_update_env
    fi

    echo "Project environment is set up"
}


func_update_env() {
    # Update requirements
    pip2pi ${PACKAGES_ROOT} -r ${SOURCE_ROOT}/requirements.txt
    ${ENV_ROOT}/bin/pip install --index-url=file://${PACKAGES_ROOT} -r ${SOURCE_ROOT}/requirements.txt --upgrade
}


func_setup_rpm() {
# Check requirements
REQUIREMENTS=(rpm-build redhat-rpm-config)
list_check programm_exists ${REQUIREMENTS[@]}
list_check programm_exists ${BUILD_REQUIREMENTS[@]}

# Create directory structure
echo -n "Creating ${HOME}/rpmbuild structure... "
mkdir -p ${HOME}/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS,tmp}
echo "OK"

# Create rpmmacros
echo -n "Creating ${HOME}/.rpmmacros... "
(
cat <<'EOF'
%_topdir %(echo $HOME)/rpmbuild
%_tmppath %(echo $HOME)/rpmbuild/tmp
EOF
) > ${HOME}/.rpmmacros
echo "OK"

echo "RPM environment is up"
}

func_build_rpm() {
# Check RPM env
if [ ! -d "${HOME}/rpmbuild" || ! -f "${HOME}/.rpmmacros" ]; then
    func_setup_rpm
fi

# Prepare local
echo -n "Getting version and release... "
VERSION=$(${BIN} getversion | tail -1) || "undefined"
RELEASE=$(date +%s)
echo "${VERSION}-${RELEASE}"

# Copy SPEC file
echo -n "Copying ${SOURCE_ROOT}/share/website.spec to ${HOME}/rpmbuild/SPECS/... "
cp ${SOURCE_ROOT}/share/website.spec ${HOME}/rpmbuild/SPECS/
echo "OK"

# Build RPM
PARAMS=()

PARAMS+=("--define \"version ${VERSION}\"")
PARAMS+=("--define \"release ${RELEASE}\"")

LOCAL_PYPI=${PACKAGES_ROOT}/simple
if [ -d ${LOCAL_PYPI} ]; then
    echo "Use pip2pi: ${LOCAL_PYPI}"
    PYPI="file://${LOCAL_PYPI}"
fi
PARAMS+=("--define \"__pypi ${PYPI}\"")

if $IS_QUIET; then
    PARAMS+=("--quiet")
fi

if $IS_PURGE; then
    echo -n "Purging RPMS directory... "
    rm -Rf ${HOME}/rpmbuild/RPMS/* > /dev/null 2>&1
    echo "OK"
fi

RPMBUILD="rpmbuild -bb ${HOME}/rpmbuild/SPECS/${SPEC} ${PARAMS[@]}"
echo "Building with command: ${RPMBUILD}"

# Find for "Wrote: /home/<username>/rpmbuild/RPMS/x86_64/<>programm name>-<version>-<release>.x86_64.rpm"
RESULT=$(eval ${RPMBUILD} | awk '/Wrote:/ {print $2}')
RETVAL=$?

if [ $RETVAL -eq 0 ]; then
    echo "Building complete"
    echo "Install command: sudo rpm -Uvh ${RESULT}"
else
    echo "Building failed"
fi
}


# Main
echo "Source root: ${SOURCE_ROOT}"
echo "Project root: ${PROJECT_ROOT}"

# Check for virtualenv
if ! command_exists virtualenv; then
    echo "virtualenv needed"
    exit 1
fi

CMD=$1
if [ ! -d ${ENV_ROOT} ]; then
    CMD=func_setup_env
fi

# Process
if [[ -z ${CMD} || ! ${CUSTOM_COMMANDS[*]} =~ ${CMD} ]] ; then
    ${ENV_ROOT}/bin/python ${SOURCE_ROOT}/manage.py $@
else
    FUNC="func_${CMD}"
    echo "Calling ${FUNC}"
    ${FUNC}
fi

exit $RETVAL