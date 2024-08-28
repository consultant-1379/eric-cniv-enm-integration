#!/usr/bin/python3
# pylint: disable=invalid-name

# --------------------------------------------------------------------------
#  COPYRIGHT Ericsson 2023
#
#  The copyright to the computer program(s) herein is the property of
#  Ericsson Inc. The programs may be used and/or copied only with written
#  permission from Ericsson Inc. or in accordance with the terms and
#  conditions stipulated in the agreement/contract under which the
#  program(s) have been supplied.
#
# --------------------------------------------------------------------------

"""
Cleanup docker registry. Script will read  images.txt.retagged for the list of images need to be deleted, and
 checks the registry and deletes the images.
"""

import argparse
import getpass
import logging
import requests
import urllib3
import time
import sys
from os import path
import os

# Logging
DEFAULT_LOGFORMAT = ('%(asctime)s [cniv-docker-registry-cleanup]'
                     '[%(levelname)s] %(message)s')
logging.basicConfig(format=DEFAULT_LOGFORMAT,
                    level=logging.INFO)

# Disable warnings from local registry
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
urllib3.disable_warnings(urllib3.exceptions.SubjectAltNameWarning)

# Init global variable
repo_url = ''
images_in_repo = dict()
images_retagged = dict()
manifests_to_delete = dict()


# Colors
class colours:
    """
    colours
    """
    OK = '\033[92m'
    WARN = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'


# Init parser
parser = argparse.ArgumentParser()
parser.add_argument("--user",
                    help="Username for the Docker registry")
args = parser.parse_args()
user = args.user
imgFile = "../../Files/images.txt.retagged"
script_path = os.path.realpath(os.path.dirname(__file__))
image_path = os.path.join(script_path, imgFile)

if not path.isfile(image_path):
    print(colours.FAIL + "'images.txt.retagged' file was not found to determine which images to be deleted"
                         "." + colours.ENDC)
    sys.exit()
if not user:
    user = input("Please enter username for the registry: ")

password = os.getenv("DOCKER_REGISTRY_PASSWORD")
if not password:
    password = getpass.getpass("Please enter password for the registry: ")


def ask_yes_no(question):
    """
    Asks "YeS" or "no" question
    """
    expected_answer = {'YeS': True, 'no': False}
    answer = input(colours.WARN + question + colours.ENDC)
    if answer in expected_answer:
        return expected_answer[answer]
    print("Please answer 'YeS' or 'no'")
    return ask_yes_no(question)


def check_file_repo():
    """
    check if file, repo and credentials are correct
    """
    global repo_url
    try:
        with open(image_path, "r") as file:
            line = file.readline()
            repo_url = 'https://' + line.split('/', 1)[0] + '/v2/'
        file.close()
    except IOError:
        print(colours.FAIL + "Error: File does not appear to exist or is not readable")
        sys.exit()
    try:
        response = requests.get(repo_url,
                                verify=False,
                                auth=(user, password))
        if response.status_code == 200:
            print(colours.OK + "Docker registry \"" + repo_url + "\" will be used" + colours.ENDC)
            return 0
        if response.status_code == 401:
            print(colours.FAIL + "Please check credentials provided" + colours.ENDC)
            sys.exit()
    except requests.exceptions.RequestException:
        print(
            colours.FAIL + "Error: could not connect with Docker Registry. Please check if the following registry is "
                           "available: " + repo_url + " " + colours.ENDC)
        sys.exit()
    # function should exit before here, but in case it didn't, return an error
    return 0


def get_manifest(image, tag):
    """
    get docker manifest for a given images
    """
    headers = {
        'Accept': 'application/vnd.docker.distribution.manifest.v2+json',
    }
    response = requests.get(repo_url + image + '/manifests/' + tag,
                            verify=False,
                            headers=headers,
                            auth=(user, password))
    manifest = response.headers.get('Docker-Content-Digest')
    return manifest


def get_images():
    """
    get the list of images from the file and from the registry
    """
    file = open(image_path, 'r')
    for line in file.readlines():
        image = line.split('/', 1)[1].split(':')[0]
        images_retagged.__setitem__(image, [line.split(':')[-1].rstrip()])
        response = requests.get(repo_url + image + '/tags/list',
                                verify=False,
                                auth=(user, password))
        if 'tags' in response.json() and response.json()['tags']:
            images_in_repo.__setitem__(image, response.json()['tags'])
    file.close()


def delete_manifest(manifest, image, retry):
    """
    Deleted docker image by manifest
    """
    if retry == 4:
        print(colours.FAIL + 'Deleting of image ' + image + ' failed. Please retry later.' + colours.ENDC)
        return 1
    headers = {
        'Accept': 'application/vnd.docker.distribution.manifest.v2+json',
    }
    response = requests.delete(repo_url + image + '/manifests/' + manifest,
                               headers=headers,
                               verify=False,
                               auth=(user, password))
    if response.status_code == 202:
        print('Image ' + image + ' was deleted')
    else:
        time.sleep(3)
        delete_manifest(manifest, image, retry + 1)


def delete_images():
    """
    delete images from the registry
    """
    redundant_images = []
    for image in images_in_repo:
        for tag in images_in_repo[image]:
            manifest = get_manifest(image, tag)
            if manifest:
                manifests_to_delete.__setitem__(manifest, image)
                redundant_images.append(image + ':' + tag)

    if not redundant_images:
        print("Nothing to delete. Exiting...")
        return 0

    print(colours.WARN + "Following", len(redundant_images),
          "images will be deleted:" + colours.ENDC + "\n" + "\n".join(redundant_images))
    confirm = ask_yes_no("Do you want to delete the images (YeS/no)? ")
    if confirm:
        for manifest in manifests_to_delete:
            delete_manifest(manifest, manifests_to_delete[manifest], 0)


def main():
    check_file_repo()
    get_images()
    delete_images()


if __name__ == "__main__":
    main()
