#!/bin/sh
usage() {
cat << EOF
usage: $0 [command] -s url -n name [options]

This script helps to build RPM package from python code
Available commands: build_rpm (default), setup_rpm, check_env, setup_env, update_env

OPTIONS:
    -s url       Path to directory with source code or git url
    -n name      Name of project

    -p url       PyPi url
    -e           Path to virtualenv directory
    -b           Force virtualenv build

    -w path      Working directory
    -f path      Path to SPEC-file
    -h           Show this message

    -q           Quite RPM building
    -b           Force rebuild virtualenv
    -t           Target architecture (e.g. x86_64 or i686)
    -d           Do not clear RPM directory before building
EOF
}


### PREDEFINED ###
[ -d ~/.local/bin ] && PATH=~/.local/bin:$PATH
BIN=$(readlink "${0}")
[ -z ${BIN} ] && BIN=${0}
BIN_ROOT="$(cd $(dirname "${BIN}"); pwd)"
RETVAL=0

### SETTINGS ###
VIRTUALENV_BIN="virtualenv"
SOURCE=""
SPEC=""
ENV_ROOT=""
PROJECT_NAME=""
IS_GIT=true
IS_DJANGO=false
IS_PURGE=true  # Clean RPM directory before build
IS_QUIET=false  # rpmbuild with --quite option
#PYPI="http://pypi.python.org/‎"  # pypi index-url
BUILD_ENV=false

WITHOUT_CHECK=false

ENV_DIR="env"
SOURCE_DIR="src"

WORKING_DIR="projects"
PIP_CACHE_DIR="_cache"
TMP_DIR="_tmp"
DEPLOY_DIR="deploy"
TARGET="x86_64"
CMD="build_rpm"


command_exists() {
    command -v "$1" > /dev/null 2>&1
}


join() {
    local IFS="$1"
    shift
    echo "$*"
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
    curl -O https://bootstrap.pypa.io/ez_setup.py 
    python ez_setup.py --user
    easy_install --prefix=$HOME/.local virtualenv pip
}


func_check_env() {
    # Check for virtualenv
    ! command_exists ${VIRTUALENV_BIN} && func_prepare

    [ ! -d ${SOURCE_ROOT} ] && mkdir -p ${SOURCE_ROOT}
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
                echo "(from directory)"
                #cp -R ${SOURCE}/* ${SOURCE_ROOT} && rm -Rf ${SOURCE_ROOT}/.git
                rsync -ird --delete-excluded --filter=':- .gitignore' --exclude=".git" ${SOURCE}/ ${SOURCE_ROOT}
            else
                echo "(from repository) "
                rm -Rf ${SOURCE_ROOT}
                git clone --recursive -q ${SOURCE} ${SOURCE_ROOT}
                R=$?
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

    [ -z ${SPEC} ] && SPEC=$(find ${DEPLOY_ROOT} -type f -name "*.spec" | head -1) || SPEC="$(cd $(dirname ${SPEC}); pwd)/$(basename ${SPEC})"
    if [ -z ${SPEC} ] || [ ! -f ${SPEC} ]; then
        echo "SPEC-file does not exists" >&2
        exit 1
    else
        echo "Use SPEC-file: ${SPEC}"
    fi

    # Setup virtualenv if needed
    if [ ! -z ${ENV_SOURCE} ] && [ -d ${ENV_SOURCE} ]; then
        echo -n "Copying virtualenv... "
        if cp -R ${ENV_SOURCE}/* ${ENV_ROOT}; then
            find ${ENV_ROOT} -type f -name "*.py[co]" -delete
            find ${ENV_ROOT} -type f -exec sed -i "s:${ENV_SOURCE}:${ENV_ROOT}:" {} \;
            echo "OK"
        else
            echo "FAIL"
        fi
    else
        if [ ! -d ${ENV_ROOT} ] || $BUILD_ENV ; then
            func_setup_env
        else
            echo "Continue without checking requirements"
        fi
    fi

    # Collect static
    if $IS_DJANGO; then
        managepy collectstatic --noinput
        managepy --help
        echo -n "Collect static... "

        if managepy collectstatic --noinput; then
            echo "OK"
        else
            echo "FAIL"
        fi
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
    if ! $IS_DJANGO || ! managepy validate || $BUILD_ENV ; then
        echo "Install requirements... "
        func_update_env
    fi

    echo "Project environment is up"
}


func_update_env() {
    # Check build requirements
    echo "Checking build requirements"
    BUILD_REQUIRES=( $(find ${DEPLOY_ROOT} -type f -name "build_requires.txt" -exec cat {} \;) )
    # echo "BUILD REQUIRES $(join , ${BUILD_REQUIRES[@]})"
    list_check programm_exists ${BUILD_REQUIRES[@]}

    # Update local requirements
    echo "Updating local requirements"
    if ${ENV_ROOT}/bin/python ${ENV_ROOT}/bin/pip install -r ${SOURCE_ROOT}/requirements.txt --upgrade --index-url ${PYPI} --timeout=10; then
        virtualenv --relocatable ${ENV_ROOT}
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
    cp ${BIN_ROOT}/share_examples/rpmmacros ${HOME}/.rpmmacros
    echo "OK"

    echo "RPM environment is up"
}


func_build_rpm() {
    # Check RPM env
    if [ ! -d "${HOME}/rpmbuild" ] || [ ! -f "${HOME}/.rpmmacros" ]; then
        func_setup_rpm
    fi

    # Check Python env
    func_check_env

    # Prepare local
    echo -n "Getting version and release... "
    VERSION=$(cat ${SOURCE_ROOT}/changelog.txt | head -n 1) || "undefined"
    RELEASE=$(date +"${RELEASE_FMT}")
    echo "${VERSION}-${RELEASE}"

    # Copy SPEC file
    #echo -n "Copying ${SPEC} to ${HOME}/rpmbuild/SPECS/... "
    #cp ${SPEC} ${HOME}/rpmbuild/SPECS/
    #echo "OK"

    # Build RPM
    PARAMS=()

    PARAMS+=("--define \"version ${VERSION}\"")
    PARAMS+=("--define \"release ${RELEASE}\"")

    PARAMS+=("--define \"name ${PROJECT_NAME}\"")
    PARAMS+=("--define \"source ${PROJECT_ROOT}\"")

    REQUIRES=$(find ${DEPLOY_ROOT} -type f -name "requires.txt" -exec cat {} \; | tr "\n" ",")
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
    RPMBUILD="rpmbuild -bb ${SPEC} ${PARAMS[@]} --target=${TARGET}"
    echo "Building with command: ${RPMBUILD}"

    if [ ${RPMBUILD} != "x86_64" ]; then
        export CC="gcc -m32"
    fi

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


### MAIN ###
while [ -n "$1" ]; do
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
            ENV_SOURCE=$1
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
        -b | --build )
            BUILD_ENV=true
            ;;
        -t | --target )
            shift
            TARGET=$1
            ;;
        --releasefmt )
            shift
            RELEASE_FMT=$1
            ;;
        build_rpm | setup_rpm | check_env | setup_env | update_env )
            CMD=$1
            ;;
        -h | --help | * )
            [ -n "$1" ] && echo "Bad option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

if [ "$CMD" != "setup_rpm" ]; then
    if [ -z "$SOURCE" ]; then
        echo 'No source' >&2
        usage
        exit 1
    fi

    # is git ot just folder
    [ -d "${SOURCE}" ] && ([ ! -d ${SOURCE}/.git ] && IS_GIT=false || SOURCE="$(cd ${SOURCE}; pwd)")

    # working directory bin/tmp or attr
    #[ -z ${WORKING_ROOT} ] && WORKING_ROOT="${BIN_ROOT}/${WORKING_DIR}" || WORKING_ROOT="$(cd ${WORKING_ROOT}; pwd)"
    [ -z ${WORKING_ROOT} ] && WORKING_ROOT="/tmp" || WORKING_ROOT="$(cd ${WORKING_ROOT}; pwd)"
    PIP_CACHE_ROOT="${WORKING_ROOT}/${PIP_CACHE_DIR}"
    TMP_ROOT="${WORKING_ROOT}/${TMP_DIR}"

    # name and path to project inside working directory
    [ -z ${PROJECT_NAME} ] && PROJECT_NAME="$(basename ${SOURCE})"
    PROJECT_ROOT="${WORKING_ROOT}/${PROJECT_NAME}"

    # path to directory with source code
    SOURCE_ROOT="${PROJECT_ROOT}/${SOURCE_DIR}"
    ENV_ROOT="${PROJECT_ROOT}/${ENV_DIR}"
    DEPLOY_ROOT="${SOURCE_ROOT}/${DEPLOY_DIR}"

    # is django
    [ -f ${SOURCE_ROOT}/manage.py ] && IS_DJANGO=true

    # pypi repo
    [ -z ${PYPI} ] && PYPI="https://pypi.python.org/simple"

    # release format
    [ -z ${RELEASE_FMT} ] && RELEASE_FMT="%Y.%m.%dT%H.%M.%S"

    echo -n "Source: ${SOURCE} " && $IS_GIT && echo "(GIT)" || echo
    echo "Project name: ${PROJECT_NAME}"
    echo "PyPi: ${PYPI}"
    echo "Working directory: ${WORKING_ROOT}"
    echo "Virtualenv directory: ${ENV_ROOT}"
    echo
    echo "Source root: ${SOURCE_ROOT}"
    echo "Project root: ${PROJECT_ROOT}"
fi

FUNC="func_${CMD}"

echo
echo "Calling ${FUNC}"

${FUNC}

exit $RETVAL
