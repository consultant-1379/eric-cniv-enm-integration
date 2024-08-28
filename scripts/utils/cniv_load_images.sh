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
#       File name: cniv_load_image.sh
#
#
#--------------------------------------------------------------------------


RED="\033[1;31m"
GREEN="\033[1;32m"
NOCOLOR="\033[0m"
LOG_FILE=$1
DOCKER_IMAGE_TAR=$2
IMAGE_LIST=$3


logger() {
   echo -e "$(date '+%Y-%m-%d %H:%M:%S:')" "$@" | tee -a "${LOG_FILE}"
}


logger "Loading [$DOCKER_IMAGE_TAR]..."

if [ ! -f "${DOCKER_IMAGE_TAR}" ] ; then
   logger "Could not find docker image tar file ${RED}$DOCKER_IMAGE_TAR${NOCOLOR}"
   exit 1
fi
if [ ! -f "${IMAGE_LIST}" ] ; then
   logger "Could not find docker image list file ${RED}$IMAGE_LIST${NOCOLOR}"
   exit 1
fi

sudo docker load --input "${DOCKER_IMAGE_TAR}"

resultCode=$?
if [ ${resultCode} -ne 0 ] ; then
   logger "${RED}Unexpected Error when performing docker load of images${NOCOLOR}"
   exit 1
fi

LIST_OF_DOCKER_IMAGES=`sudo docker image list | awk '{print $1":"$2;}'`

for IMAGE_NAME_FROM_FILE in $(cat $IMAGE_LIST)
do
   if [[ ${LIST_OF_DOCKER_IMAGES} = *"$IMAGE_NAME_FROM_FILE"*  ]] ; then
       logger "Image ${GREEN}$IMAGE_NAME_FROM_FILE${NOCOLOR} Loaded"
   else
       logger "Could not find images ${RED}$IMAGE_NAME_FROM_FILE${NOCOLOR}"
       exit 1
   fi
done

