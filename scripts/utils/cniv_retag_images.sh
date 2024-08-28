#!/bin/bash
#------------------------------------------------------------------------
#
#
#       COPYRIGHT (C) 2023                 ERICSSON AB, Sweden
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
#       File name: cniv_retag_images.sh
#
#       This script re-tags images so that they no longer point to the image
#       registry where they were built and now point to the target kubernetes
#       deployment environment.
#
#       e.g
#       Re-tag the following-:
#          armdocker.rnd.ericsson.se/proj-eson/identity-service:0.1.0-161
#       To -:
#          k8s-registry.eccd.local/proj-eson/identity-service:0.1.0-161
#
#
#--------------------------------------------------------------------------

RED="\033[1;31m"
GREEN="\033[1;32m"
NOCOLOR="\033[0m"
LOG_FILE=$1
IMAGE_LIST=$2
DOCKER_REGISTRY_URL=$3
IMAGE_LIST_RETAGGED=${IMAGE_LIST}.retagged

logger() {
   echo -e "$(date '+%Y-%m-%d %H:%M:%S:')" "$@" | tee -a "${LOG_FILE}"
}

sudo rm -f "${IMAGE_LIST_RETAGGED}"
sudo touch "${IMAGE_LIST_RETAGGED}"
sudo chmod 776 "${IMAGE_LIST_RETAGGED}"

logger "Writing retagged image names to $IMAGE_LIST_RETAGGED..."

if [ ! -f "${IMAGE_LIST}" ] ; then
   logger "Could not find docker image list file ${RED}$IMAGE_LIST${NOCOLOR}"
   exit 1
fi

for currentImageName in $(cat $IMAGE_LIST)
do
    source_docker_registry_url=$(echo ${currentImageName}|cut -d'/' -f1)

    target_image_name=$(echo ${currentImageName} | sed "s#${source_docker_registry_url}#${DOCKER_REGISTRY_URL}#g")

    logger "Retagging [$currentImageName] to [$target_image_name]..."
    sudo docker tag ${currentImageName} ${target_image_name}
    resultCode=$?
    if [ ${resultCode} -ne 0 ] ; then
        logger "${RED}Unexpected Error when performing docker tag of images${NOCOLOR}"
        exit 1
    fi

    sudo docker rmi --force ${currentImageName}
    resultCode=$?
    if [ ${resultCode} -ne 0 ] ; then
        logger "${RED}Unexpected Error when performing docker rmi of old images${NOCOLOR}"
        exit 1
    fi


    echo ${target_image_name} >> ${IMAGE_LIST_RETAGGED}
done


LIST_OF_DOCKER_IMAGES=`sudo docker image list | awk '{print $1":"$2;}'`

for RETAGGED_IMAGE_NAME in $(cat $IMAGE_LIST_RETAGGED)
do
   if [[ ${LIST_OF_DOCKER_IMAGES} = *"$RETAGGED_IMAGE_NAME"*  ]] ; then
       logger "Image ${GREEN}$RETAGGED_IMAGE_NAME${NOCOLOR} Re-Tagged"
   else
       logger "Could not find image ${RED}$RETAGGED_IMAGE_NAME${NOCOLOR}"
       logger "All images not loaded.......................................${RED}NOT OK${NOCOLOR}"
       exit 1
   fi
done