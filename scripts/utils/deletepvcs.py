#!/usr/bin/python3

import subprocess
import json

print("This script will delete PVC's after CNIV has been uninstalled")
namespace = input("Enter namespace: ")

pvcs = subprocess.check_output(["kubectl", "get", "pvc", "-n", namespace, "-o", "json"])
data = json.loads(pvcs)

for metadata in data['items']:
    pvcname = metadata['metadata']['name']
    print(pvcname)

answer = input("These PVC's are about to be deleted. Would you like to continue? 'Y' or 'N'?: ")

if answer.lower() == 'y':
    for metadata in data['items']:
        pvcname = metadata['metadata']['name']
        print("Deleting pvc: {} ".format(pvcname))
        subprocess.run(["kubectl", "delete", "pvc", "-n", namespace, pvcname])

else:
    print("No PVC's will be deleted.")