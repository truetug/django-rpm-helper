#!/bin/sh
usage() {
cat << EOF
usage: $0 [options]

This script helps to build RPM package from python code

OPTIONS:
   -h           Show this message
   -s url       Path to directory with source or git url
   -p url       PyPi url
   -n name      Name of project
   -e           Path to virtualenv directory
   -w path      Working directory
   -d           Do not clear RPM directory before building
   -q           Quite building
   -x           Do not check virtualenv
   -f path      Path to SPEC-file
EOF
}

# predifined
[ -d ~/.local/bin ] && PATH=~/.local/bin:$PATH
BIN=$(readlink "${0}")
[ -z ${BIN} ] && BIN=${0}
BIN_ROOT="$(cd $(dirname "${BIN}"); pwd)"
RETVAL=0

# settings
VIRTUALENV_BIN="virtualenv"
SOURCE=""
SPEC=""
ENV_ROOT=""
PROJECT_NAME=""
IS_GIT=true
IS_DJANGO=false
IS_PURGE=true # Clean RPM directory before build
IS_QUIET=false # rpmbuild with --quite option
#PYPI="http://pypi.python.org/‎" # pypi index-url

WITHOUT_CHECK=false
WITHOUT_PIP2PI=false

ENV_DIR="env"
SOURCE_DIR="src"

WORKING_DIR="projects"
PIP2PI_DIR="_packages"
PIP_CACHE_DIR="_cache"
TMP_DIR="_tmp"

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
        -n | --name )
            shift
            PROJECT_NAME=$1
            ;;
        -e | --env )
            shift
            ENV_ROOT=$1
            ;;
        -d | --dirty )
            IS_PURGE=false
            ;;
        -q | --quite )
            IS_QUIET=true
            ;;
        -w | --workingroot )
            shift
            WORKING_ROOT=$1
            ;;
        -f | --file )
            shift
            SPEC=$1
            ;;
        -x | --without-check )
            WITHOUT_CHECK=true
            ;;
        --without-pip2pi )
            WITHOUT_PIP2PI=true
            ;;
        -h | --help | * )
            usage
            exit 1
            ;;
    esac
    shift
done

if [ -z "${SOURCE}" ]; then
    echo 'No source' >&2
    usage
    exit 1
fi

# is git ot just folder
[ -d "${SOURCE}" ] && ([ ! -d ${SOURCE}/.git ] && IS_GIT=false || SOURCE="$(cd ${SOURCE}; pwd)")

# working directory bin/tmp or attr
#[ -z ${WORKING_ROOT} ] && WORKING_ROOT="${BIN_ROOT}/${WORKING_DIR}" || WORKING_ROOT="$(cd ${WORKING_ROOT}; pwd)"
[ -z ${WORKING_ROOT} ] && WORKING_ROOT="/tmp" || WORKING_ROOT="$(cd ${WORKING_ROOT}; pwd)"
PIP2PI_ROOT="${WORKING_ROOT}/${PIP2PI_DIR}"
PIP_CACHE_ROOT="${WORKING_ROOT}/${PIP_CACHE_DIR}"
TMP_ROOT="${WORKING_ROOT}/${TMP_DIR}"

# name and path to project inside working directory
[ -z ${PROJECT_NAME} ] && PROJECT_NAME="$(basename ${SOURCE})"
PROJECT_ROOT="${WORKING_ROOT}/${PROJECT_NAME}"

# path to directory with source code
SOURCE_ROOT="${PROJECT_ROOT}/${SOURCE_DIR}"
[ -z ${ENV_ROOT} ] && ENV_ROOT="${PROJECT_ROOT}/${ENV_DIR}"

# is django
[ -f ${SOURCE_ROOT}/manage.py ] && IS_DJANGO=true

# pypi repo
[ -z ${PYPI} ] && PYPI="http://pypi.python.org/simple"

echo -n "Source: ${SOURCE} " && $IS_GIT && echo "(GIT)" || echo
echo "Project name: ${PROJECT_NAME}"
echo "PyPi: ${PYPI}"
echo "Working directory: ${WORKING_ROOT}"
echo "Virtualenv directory: ${ENV_ROOT}"
echo


# functions
command_exists() {
    command -v "$1" > /dev/null 2>&1
}


programm_exists() {
    if ! command_exists rpm; then
        echo "This program only for RPM based distributives" >&2
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


func_prepare() {
    [ ! -d ${TMP_ROOT} ] && mkdir -p ${TMP_ROOT}
    cd ${TMP_ROOT}
    curl -O http://python-distribute.org/distribute_setup.py
    python distribute_setup.py --user
    easy_install virtualenv pip pip2pi
}


func_check_env() {
    # Check for virtualenv
    ! command_exists ${VIRTUALENV_BIN} && func_prepare

    [ ! -d ${SOURCE_ROOT} ] && mkdir -p ${SOURCE_ROOT}
    [ ! -d ${PIP2PI_ROOT} ] && mkdir -p ${PIP2PI_ROOT}
    [ ! -d ${PIP_CACHE_ROOT} ] && mkdir -p ${PIP_CACHE_ROOT}

    # Clonning or updating source if needed
    echo
    if $IS_GIT; then
        if [ ! -d ${SOURCE_ROOT} ]  || [ ! -d ${SOURCE_ROOT}/.git ]; then
            if [ -z "${SOURCE}" ]; then
                echo "Git source is undefined" >&2
                exit 1
            fi

            echo -n "Getting source from ${SOURCE}... "
            if [ -d ${SOURCE} ]; then
                echo -n "(${SOURCE}/* > ${SOURCE_ROOT})"
                echo -n "(from directory)"
                #cp -R ${SOURCE}/* ${SOURCE_ROOT} && rm -Rf ${SOURCE_ROOT}/.git
                rsync -ird --filter=':- .gitignore' --exclude=".git" ${SOURCE}/ ${SOURCE_ROOT}
            else
                echo -n "(from repository) "
                rm -Rf ${SOURCE_ROOT}
                git clone --recursive -q ${SOURCE} ${SOURCE_ROOT}
            fi
        else
            echo -n "Updating source... "
            cd ${SOURCE_ROOT}
            git checkout .
            R=$?
            git pull && git submodule init && git submodule update && git submodule status | grep "requirements.txt" && func_update_env
        fi
    else
        echo -n "Copying source... "
        cp -R ${SOURCE}/* ${WORKING_ROOT}
    fi

    [ -z $R ] && R=$?

    if [ $R -ne 0 ]; then
         echo "FAIL"
         echo "Error while getting source" >&2
         exit 1
    fi

    echo "OK"


    [ -z ${SPEC} ] && SPEC=$(find ${SOURCE_ROOT} -type f -name "*.spec" | head -1) || SPEC="$(cd $(dirname ${SPEC}); pwd)/$(basename ${SPEC})"
    if [ -z ${SPEC} ] || [ ! -f ${SPEC} ]; then
        echo "SPEC-file does not exists" >&2
        exit 1
    else
        echo "Use SPEC-file: ${SPEC}"
    fi

    # Setup virtualenv if needed
    if ! $WITHOUT_CHECK && (! $IS_DJANGO || ([ ! -d ${ENV_ROOT} ] || ! managepy validate)); then
        func_setup_env
    else
        echo "Continue without check"
    fi
}


func_setup_env() {
    # Create virtualenv if not exists
    if [ ! -f ${ENV_ROOT}/bin/python ] ; then
        echo "Creating virtualenv... "
        if ! ${VIRTUALENV_BIN} --distribute ${ENV_ROOT}; then
            echo "Error while creating virtualenv" >&2
            exit 1
        fi

        # Update distribute, because default version is too old
        ${ENV_ROOT}/bin/easy_install -U distribute
    fi

    # Update requirements
    if ! $IS_DJANGO || ! managepy validate ; then
        echo "Install requirements... "
        func_update_env
    fi

    echo "Project environment is set up"
}


func_update_env() {
    # Check build requirements
    echo "Checking build requirements"
    BUILD_REQUIRES=( $(find ${SOURCE_ROOT} -type f -name "build_requires.txt" -exec cat {} \;) )
    echo "BUILD REQUIRES ${BUILD_REQUIRES}"
    list_check programm_exists ${BUILD_REQUIRES[@]}

    # Update local requirements
    echo "Updating local requirements"
    ##[ -d ${PIP2PI_ROOT} ] && PYPI=file://${PIP2PI_ROOT}/simple
    if ${ENV_ROOT}/bin/pip install -r ${SOURCE_ROOT}/requirements.txt --upgrade --index-url ${PYPI} --timeout=10 --use-mirrors --download-cache ${PIP_CACHE_ROOT}; then
        virtualenv --relocatable ${ENV_ROOT}

        # http%3A%2F%2Fpypi.mail.ru%2Fpackages%2Fsource%2Fg%2Fgunicorn%2Fgunicorn-0.17.2.tar.gz
        ##echo -n "Store cached packages..."
        ##find . -type f -name "*.tar.gz" |
        ##sed -e "s/.*%2F\(.*\)/\0 \1/g" |
        ##while read path_from path_to; do mv ${path_from} ${PIP2PI_ROOT}/${path_to}; done
        ##dir2pi ${PIP2PI_ROOT}
        ##echo "OK"
    else
        echo "Problem with virtualenv" >&2
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

    # Copy rpmmacros
    echo -n "Copying ${HOME}/.rpmmacros... "
    cp ${BIN_ROOT}/share_examples/rpmmacros.sh ${HOME}/.rpmmacros
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
    #echo -n "Copying ${SPEC} to ${HOME}/rpmbuild/SPECS/... "
    #cp ${SPEC} ${HOME}/rpmbuild/SPECS/
    #echo "OK"

    # Build RPM
    PARAMS=()

    PARAMS+=("--define \"version ${VERSION}\"")
    PARAMS+=("--define \"release ${RELEASE}\"")

    PARAMS+=("--define \"source0 ${SOURCE_ROOT}\"")
    PARAMS+=("--define \"source1 ${ENV_ROOT}\"")

    REQUIRES=$(find ${SOURCE_ROOT} -type f -name "requires.txt" -exec cat {} \; | tr "\n" ",")
    if [ ! -z "${REQUIRES}" ]; then
        echo "Use install requirements: ${REQUIRES}"
        PARAMS+=("--define \"requires ${REQUIRES}\"")
    fi

    $IS_QUIET && PARAMS+=("--quiet")

    if $IS_PURGE; then
        echo -n "Purging RPMS directory... "
        find ${HOME}/rpmbuild/RPMS/ -name "*.rpm" -delete
        echo "OK"
    fi

    echo
    RPMBUILD="rpmbuild -bb ${SPEC} ${PARAMS[@]}"
    echo "Building with command: ${RPMBUILD}"

    if eval ${RPMBUILD}; then
        echo
        echo "Building complete"

        RESULT=$(ls -1t $(find ${HOME}/rpmbuild/RPMS/ -name "*.rpm") | head -n 1)
        if [ -n ${RESULT} ]; then
            echo "Install command: sudo rpm -Uvh ${RESULT}"
        fi
    else
        echo "Building failed" >&2
        exit 1
    fi
}


# Main
echo "Source root: ${SOURCE_ROOT}"
echo "Project root: ${PROJECT_ROOT}"
CMD=$1

func_check_env

# TODO: make binary for any command
# Copy bin-file if django and no bin present
##if $IS_DJANGO && [ ! -f ${SOURCE_ROOT}/bin/manage.sh ]; then
##    echo -n "Copying runfile... "
##    mkdir -p ${SOURCE_ROOT}/bin/
##    cp ${BIN_ROOT}/bin_examples/manage.sh ${SOURCE_ROOT}/bin/
##    echo "OK"
##fi

[ -z ${CMD} ] && CMD="build_rpm"
FUNC="func_${CMD}"
echo
echo "Calling ${FUNC}"
${FUNC}

exit $RETVAL
