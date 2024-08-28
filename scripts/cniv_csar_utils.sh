#!/bin/bash
#------------------------------------------------------------------------
#
#
#       COPYRIGHT (C) 2023                  ERICSSON AB, Sweden
#
#       The  copyright  to  the document(s) herein  is  the property of
#       Ericsson Radio Systems AB, Sweden.
#
#       The document(s) may be used  and/or copied only with the written
#       permission from Ericsson Radio Systems AB  or in accordance with
#       the terms  and conditions  stipulated in the  agreement/contract
#       under which the document(s) have been supplied.
#
#------------------------------------------------------------------------
#
#
#       File name: cniv_csar_utils.sh
#
#
#--------------------------------------------------------------------------
#

SCRIPTPATH="$( cd "$(dirname "$0")" || exit ; pwd -P )"
RED="\033[1;31m"
GREEN="\033[1;32m"
NOCOLOR="\033[0m"
PACKAGE_NAME="cniv_csar_utils"
DATE=$(date '+%Y-%m-%d-%H:%M:%S')
PACKAGE_LOG="/tmp/${PACKAGE_NAME}_$DATE.log"
DOCKER_REGISTRY_URL="UNDEFINED"

logger() {
  echo -e "$(date '+%Y-%m-%d %H:%M:%S:')" "$@" | tee -a "${PACKAGE_LOG}"
}


printUsage() {
    echo "usage:  --docker-registry-url=<URL> "
    echo ""
    echo "./cniv_csar_utils.sh --docker-registry-url=k8s-registry.eccd.local "
    exit 1
}


load_images() {
    logger "Load ${PACKAGE_NAME} Images...."
    bash "${SCRIPTPATH}"/utils/cniv_load_images.sh "${PACKAGE_LOG}" "${SCRIPTPATH}"/../Files/images/docker.tar "${SCRIPTPATH}"/../Files/images.txt
    resultCode=$?
    if [ ${resultCode} -ne 0 ] ; then
        logger "All images not loaded.......................................${RED}NOT OK${NOCOLOR}"
        exit ${resultCode}
    else
        logger "Images loaded..................................................${GREEN}OK${NOCOLOR}"
    fi
}


retag_images() {
    logger "Re-Tag ${PACKAGE_NAME} Images...."
    bash "${SCRIPTPATH}"/utils/cniv_retag_images.sh "${PACKAGE_LOG}" "${SCRIPTPATH}"/../Files/images.txt "${DOCKER_REGISTRY_URL}"
    resultCode=$?
    if [ ${resultCode} -ne 0 ] ; then
        logger "Images not Re-tagged........................................${RED}NOT OK${NOCOLOR}"
        exit ${resultCode}
    else
        logger "Images Re-tagged................................................${GREEN}OK${NOCOLOR}"
    fi
}


push_retagged_images() {
    logger "Push Re-Tagged ${PACKAGE_NAME} Images...."
    bash "${SCRIPTPATH}"/utils/cniv_push_retagged_images.sh "${PACKAGE_LOG}" "${SCRIPTPATH}"/../Files/images.txt.retagged
    resultCode=$?
    if [ ${resultCode} -ne 0 ] ; then
        logger "Images not Pushed...........................................${RED}NOT OK${NOCOLOR}"
        exit ${resultCode}
    else
        logger "Images Pushed...................................................${GREEN}OK${NOCOLOR}"
    fi
}

#####################################################
#                    CSAR UTILS                     #
#####################################################
csar_utils() {
    logger "Performing CNIV Csar Utils Pre-Checks...."


    logger "Performing loading , retagging and pushing to docker registry"

    if [ ! "$DOCKER_REGISTRY_URL" == "UNDEFINED" ]; then
        load_images;
        logger

        retag_images;
        logger

        push_retagged_images;
        logger
    else
        logger "Skipping image loading, retagging and pushing to docker  registry."
    fi


    logger "Loading, retagging and pushing to docker registry ${PACKAGE_NAME} complete"
}



#####################################################
#                                                   #
#                    MAIN                           #
#                                                   #
#####################################################

logger "Starting cniv_csar_utils.sh script for ${PACKAGE_NAME}. Writing output to log file ${PACKAGE_LOG}"

while [ "$1" != "" ]; do
    PARAM=$(echo "$1" | awk -F= '{print $1}')
    VALUE=$(echo "$1" | awk -F= '{print $2}')
    case ${PARAM} in
        -h | --help)
            printUsage;
            ;;
        --docker-registry-url)
            DOCKER_REGISTRY_URL=${VALUE}
            ;;
        *)
            printUsage;
            ;;
    esac
    shift
done


csar_utils;

logger "Script Execution Complete. See log file ${PACKAGE_LOG}"
