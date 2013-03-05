#!/bin/sh
# Argument order = -s source -p pypi -c -q
#
# .../<anyprojectname>
#       /env - virtualenv
#       /src - source with manage.py
#       /packages - pip2pi

# .../src
#       changelog.txt
#       /share
#           website.spec
#

usage() {
cat << EOF
usage: $0 options

This script helps to build RPM package from python code

OPTIONS:
   -h           Show this message
   -s url       Path to directory with source or git url
   -p url       PyPi url
   -w path      Working directory
   -d           Do not clear RPM directory before building
   -q           Quite building
   -f path      Path to SPEC-file
EOF
}

# predifined
BIN=$(readlink "${0}")
[ -z ${BIN} ] && BIN=${0}
BIN_ROOT="$(cd $(dirname "${BIN}"); pwd)"
RETVAL=0

# settings
SOURCE=""
WORKING_DIR=""
IS_GIT=true
IS_PURGE=true # Clean RPM directory before build
IS_QUIET=false # rpmbuild with --quite option
PYPI="http://pypi.mail.ru/simple" # pypi index-url

while [ "$1" != "" ]; do
    case $1 in
        -s | --source )
            shift
            SOURCE=$1
            ;;
        -p | --pypi )
            shift
            PYPI=$1
            ;;
        -d | --dirty )
            IS_PURGE=false
            ;;
        -q | --quite )
            IS_QUIET=true
            ;;
        -w | --workdir )
            shift
            WORKING_DIR=$1
            ;;
        -f | --file )
            shift
            SPEC=$1
            ;;
        -h | --help | * )
            usage
            exit 1
            ;;
    esac
    shift
done

if [ -z $SOURCE ]; then
    echo 'No source'
    exit 1
else
    SOURCE="$(cd ${SOURCE}; pwd)"
fi

[ -z ${WORKING_DIR} ] && WORKING_DIR="${BIN_ROOT}/projects" || WORKING_DIR="$(cd ${WORKING_DIR}; pwd)"
PROJECT_NAME="$(basename ${SOURCE})"
PROJECT_ROOT="${WORKING_DIR}/${PROJECT_NAME}"
SOURCE_ROOT="${PROJECT_ROOT}/src"
PACKAGES_ROOT="${PROJECT_ROOT}/packages"
ENV_ROOT="${PROJECT_ROOT}/env"
[ -z ${SPEC} ] && SPEC="${SOURCE_ROOT}/share/website.spec"
[ -d ${SOURCE} ] && [ ! -d ${SOURCE}/.git ] && IS_GIT=false
[ -z ${PYPI} ] && PYPI="http://pypi.python.org/simple"

echo -n "Source: ${SOURCE} " && $IS_GIT && echo "(GIT)" || echo
echo "Project name: ${PROJECT_NAME}"
echo "PyPi: ${PYPI}"
echo "SPEC-file: ${SPEC}"

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


managepy() {
    ${ENV_ROOT}/bin/python ${SOURCE_ROOT}/manage.py $@ > /dev/null 2>&1
}


func_check_env() {
    # Check for virtualenv
    if ! command_exists virtualenv; then
        echo "Virtualenv is needed"
        echo "Use: sudo easy_install virtualenv"
        exit 1
    fi

    [ ! -d ${WORKING_DIR} ] && mkdir -p ${WORKING_DIR}

    # Clonning or updating source if needed
    if $IS_GIT; then
        if [ ! -d ${SOURCE_ROOT} ]; then
            if [ -z ${SOURCE} ]; then
                echo "Git source is undefined"
                exit 1
            fi
            echo -n "Clonning source from ${SOURCE}... "
            git clone -q ${SOURCE} ${SOURCE_ROOT}
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
    else
        cp -R ${SOURCE} ${WORKING_DIR}
    fi

    if [ ! -f ${SPEC} ]; then
        echo "SPEC-file does not exists"
        exit 1
    fi

    # Setup virtualenv if needed
    if [ ! -d ${ENV_ROOT} ] || ! managepy validate; then
        func_setup_env
    fi
}


func_setup_env() {
    # Create virtualenv if not exists
    if [ ! -f ${ENV_ROOT}/bin/python ] ; then
        echo "Creating virtualenv... "
        virtualenv --distribute ${ENV_ROOT}
        RETVAL=$?
        echo $RETVAL

        # Update distribute, because default version is too old
        ${ENV_ROOT}/bin/easy_install -U distribute
    fi

    # Update requirements
    if ! managepy validate ; then
        echo "Install requirements... "
        func_update_env
    fi

    echo "Project environment is set up"
}


func_update_env() {
    # Check build requirements
    BUILD_REQUIREMENTS=( $(cat ${SOURCE_ROOT}/build_requirements.txt) )
    list_check programm_exists ${BUILD_REQUIREMENTS[@]}

    # Update requirements
    #pip2pi ${PACKAGES_ROOT} -r ${SOURCE_ROOT}/requirements.txt
    #${ENV_ROOT}/bin/pip install --index-url=file://${PACKAGES_ROOT}/simple -r ${SOURCE_ROOT}/requirements.txt --upgrade
    if ${ENV_ROOT}/bin/pip install --index-url=${PYPI} -r ${SOURCE_ROOT}/requirements.txt --upgrade; then
        virtualenv --relocatable ${ENV_ROOT}
    else
        echo "Problem with virtualenv"
        exit 1
    fi
}


func_setup_rpm() {
# Check requirements
REQUIREMENTS=(rpm-build redhat-rpm-config)
list_check programm_exists ${REQUIREMENTS[@]}

# Create directory structure
echo -n "Creating ${HOME}/rpmbuild structure... "
mkdir -p ${HOME}/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS,tmp}
echo "OK"

# Create rpmmacros
echo -n "Creating ${HOME}/.rpmmacros... "
(
cat << EOF
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

func_check_env

if [ ! -f ${SOURCE_ROOT}/bin/manage.sh ]; then
    echo -n "Copying runfile... "
    mkdir -p ${SOURCE_ROOT}/bin/
    cp ${BIN_ROOT}/bin_examples/manage.sh ${SOURCE_ROOT}/bin/
    echo "OK"
fi

[ -z ${CMD} ] && CMD="build_rpm"

FUNC="func_${CMD}"
echo "Calling ${FUNC}"
${FUNC}

exit $RETVAL
