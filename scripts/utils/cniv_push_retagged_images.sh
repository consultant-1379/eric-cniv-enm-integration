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
#       File name: cniv_push_retagged_images.sh
#
#
#--------------------------------------------------------------------------


RED="\033[1;31m"
NOCOLOR="\033[0m"
LOG_FILE=$1
IMAGE_LIST_RETAGGED=$2


logger() {
   echo -e "$(date '+%Y-%m-%d %H:%M:%S:')" "$@" | tee -a "${LOG_FILE}"
}


logger "Pushing retagged images..."
if [ ! -f "${IMAGE_LIST_RETAGGED}" ] ; then
   logger "Could not find docker re-tagged image list file ${RED}$IMAGE_LIST_RETAGGED${NOCOLOR}"
   exit 1
fi

for image in $(cat $IMAGE_LIST_RETAGGED)
do
    logger "Pushing [$image]..."
    sudo docker push ${image}
    resultCode=$?
    if [ ${resultCode} -ne 0 ] ; then
        logger "${RED}Unexpected Error when performing docker push of image ${image}"
        exit 1
    fi
    sudo docker rmi --force ${image}
    resultCode=$?
    if [ ${resultCode} -ne 0 ] ; then
        logger "${RED}Unexpected Error when performing docker rmi of image ${image}"
        exit 1
    fi
done

logger "Done"

