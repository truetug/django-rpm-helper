#!/bin/sh
# .../<anyprojectname>
#       /env - virtualenv
#       /src - source with manage.py
#       /packages - pip2pi

# .../src
#       changelog.txt
#       /share
#           website.spec
#       

# settings
GIT_SOURCE=""
IS_PURGE=true # Clean RPM directory before build
IS_QUIET=false # rpmbuild with --quite option
PYPI="http://pypi.mail.ru/simple" # pypi index-url
# TODO: get from special file in project


# predifined
BIN=$(readlink "${0}")
if [ -z ${BIN} ]; then
    BIN=${0}
fi
BIN_ROOT=$(cd $(dirname "${BIN}"); pwd)
PROJECT_ROOT=$(dirname ${BIN_ROOT})
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
        echo "Install: ${TO_INSTALL[@]}"
        exit
    fi
}

func_setup_env() {
    # Create virtualenv if not exists
    if [ ! -f ${ENV_ROOT}/bin/python ] ; then
        echo "Creating virtualenv... "
        virtualenv --distribute ${ENV_ROOT}
        # Update distribute, because default version is too old
        ${ENV_ROOT}/bin/pip easy_install -U distribute
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
    #pip2pi ${PACKAGES_ROOT} -r ${SOURCE_ROOT}/requirements.txt
    #${ENV_ROOT}/bin/pip install --index-url=file://${PACKAGES_ROOT}/simple -r ${SOURCE_ROOT}/requirements.txt --upgrade
    ${ENV_ROOT}/bin/pip install --index-url=${PYPI} -r ${SOURCE_ROOT}/requirements.txt --upgrade
    virtualenv --relocatable ${ENV_ROOT}
}


func_setup_rpm() {
# Check requirements
REQUIREMENTS=(rpm-build redhat-rpm-config)
list_check programm_exists ${REQUIREMENTS[@]}
BUILD_REQUIREMENTS=( $(cat ${SOURCE_ROOT}/build_requirements.txt) )
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
if [ ! -d "${HOME}/rpmbuild" ] || [ ! -f "${HOME}/.rpmmacros" ]; then
    func_setup_rpm
fi

# Prepare local
echo -n "Getting version and release... "
VERSION=$(cat ${SOURCE_ROOT}/changelog.txt | head -n 1) || "undefined"
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
PARAMS+=("--define \"source0 ${SOURCE_ROOT}\"")
PARAMS+=("--define \"source1 ${ENV_ROOT}\"")

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
    find ${HOME}/rpmbuild/RPMS/ -name "*.rpm" -delete
    echo "OK"
fi

RPMBUILD="rpmbuild -bb ${HOME}/rpmbuild/SPECS/website.spec ${PARAMS[@]}"
echo "Building with command: ${RPMBUILD}"

if eval ${RPMBUILD}; then
    echo "Building complete"

    RESULT=$(ls -1t $(find ${HOME}/rpmbuild/RPMS/ -name "*.rpm") | head -n 1)
    if [ -n ${RESULT} ]; then
        echo "Install command: sudo rpm -Uvh ${RESULT}"
    fi

else
    echo "Building failed"
fi
}


# Main
echo "Source root: ${SOURCE_ROOT}"
echo "Project root: ${PROJECT_ROOT}"
CMD=$1

# Check for virtualenv
if ! command_exists virtualenv; then
    echo "Virtualenv is needed"
    echo "Use: sudo easy_install virtualenv"
    exit 1
fi

# Clonning or updating source if needed
if [ ! -d ${SOURCE_ROOT} ]; then
    if [ -z ${GIT_SOURCE} ]; then
        echo "Git source is undefined"
        exit 1
    fi
    echo -n "Clonning source from ${GIT_SOURCE}... "
    git clone -q ${GIT_SOURCE} ${SOURCE_ROOT}
    echo "OK"
else
    echo -n "Updating source... "
    cd ${SOURCE_ROOT}
    git checkout .
    if [ $(git pull | grep "requirements.txt") ]; then
        func_update_env
    fi
    echo "OK"
fi

# Setup virtualenv if needed
if [ ! -d ${ENV_ROOT} ]; then
    func_setup_env
fi

if [ ! -f ${SOURCE_ROOT}/bin/manage.sh ]; then
    echo -n "Copying runfile... "
    mkdir -p ${SOURCE_ROOT}/bin/
    cp ${BIN_ROOT}/bin_examples/manage.sh ${SOURCE_ROOT}/bin/
    echo "OK"
fi

if [ -z ${CMD} ]; then
    CMD="build_rpm"
fi

FUNC="func_${CMD}"
echo "Calling ${FUNC}"
${FUNC}

exit $RETVAL