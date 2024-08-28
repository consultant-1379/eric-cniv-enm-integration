#!/bin/bash
#--------------------------------------------------------------------------------
#
#
#       COPYRIGHT (C) 2024                  ERICSSON AB, Sweden
#
#       The  copyright  to  the document(s) herein  is  the property of
#       Ericsson Radio Systems AB, Sweden.
#
#       The document(s) may be used  and/or copied only with the written
#       permission from Ericsson Radio Systems AB  or in accordance with
#       the terms  and conditions  stipulated in the  agreement/contract
#       under which the document(s) have been supplied.
#
#--------------------------------------------------------------------------------
#       Conor Moran EMRNCNR conor.moran@ericsson.com
#       Version: 1.0.7
#       Guide: https://eteamspace.internal.ericsson.com/display/DEVAREA/CNIV+getlogs.sh
#--------------------------------------------------------------------------------
#       Script to save kubectl logs for each pod to a .txt file
#--------------------------------------------------------------------------------


RED='\033[0;31m'
GREEN='\033[0;32m'
LIGHTGREEN='\033[1;32m'
NC='\033[0m' # No Color

OUTPUTFILE='$(pwd)'
zip=false
valuesyaml=false
htmlonly=false
namespace='default'

scriptpath=$(realpath $(dirname $0))
globalpath="$scriptpath/eric-cniv-enm-global-values.yaml"
smallpath="$scriptpath/eric-cniv-enm-integration-small-production-values.yaml"
xlpath="$scriptpath/eric-cniv-enm-integration-extra-large-production-values.yaml"


gather_all_logs() {
  benchmarks=( `kubectl get pods -n $namespace | awk '{print $1}' | grep -v '^NAME'` )

  for name in "${benchmarks[@]}"
  do
    echo "Gathering logs for ${name}"
    kubectl logs -n $namespace ${name} >> ${name}.txt
  done
  echo -e "${GREEN}Logs collected for all pods${NC}"
}


gather_completed_logs() {
  benchmarks=( `kubectl get pods -n $namespace | grep Completed | awk '{print $1}' | grep -v '^NAME'` )

  for name in "${benchmarks[@]}"
  do
    echo "Gathering logs for ${name}"
    kubectl logs -n $namespace ${name} >> ${name}.txt
  done
  echo -e "${GREEN}Logs collected for Completed pods${NC}"
}


gather_running_logs() {
  benchmarks=( `kubectl get pods -n $namespace | grep Running | awk '{print $1}' | grep -v '^NAME'` )

  for name in "${benchmarks[@]}"
  do
    echo "Gathering logs for ${name}"
    kubectl logs -n $namespace ${name} >> ${name}.txt
  done
  echo -e "${GREEN}Logs collected for Running pods${NC}"
}


extract_storage_logs() {
  #get pod status and wait until Running
  podstatus=$(kubectl get pod storage-inspector -n $namespace -o jsonpath='{.status.phase}')
  retry=0
  until [[ $podstatus = 'Running' || $retry -gt 9 ]]
  do
    sleep 1
    podstatus=$(kubectl get pod storage-inspector -n $namespace -o jsonpath='{.status.phase}')
    echo "Waiting for storage-inspector pod to start..."
    retry=$((retry+1))
    echo "Retrying... Current state: $podstatus  Retries: $retry"
  done
  if [ ${retry} -gt 15 ]; then
    echo "Unable to determine storage-inspector pod state, cannot connect to copy logs"
  else
    echo "Copying fio output..."

    echo "Checking if /mnt/block directory exists in storage-inspector pod..."
    kubectl exec -n $namespace storage-inspector -- ls /mnt/block &>/dev/null
    block_dir_status=$?

    echo "Checking if /mnt/file directory exists in storage-inspector pod..."
    kubectl exec -n $namespace storage-inspector -- ls /mnt/file &>/dev/null
    file_dir_status=$?

    if [ $block_dir_status -ne 0 ]; then
       echo "Error: Directory /mnt/block does not exist in storage-inspector pod." >&2
    else
        echo "Copying block storage logs..."
        kubectl cp $namespace/storage-inspector:mnt/block/ ./block_storage_logs &
    fi
    if [ $file_dir_status -ne 0 ]; then
       echo "Error: Directory /mnt/file does not exist in storage-inspector pod." >&2
    else
        echo "Copying file storage logs..."
        kubectl cp $namespace/storage-inspector:mnt/file/ ./file_storage_logs &
    fi
    # Wait for both copy operations to complete
    wait $block_cp_pid
    wait $file_cp_pid
    echo "Finished copying"
    #wait longer before deleting
    sleep 3
    echo "Deleting storage inspector pod..."
    kubectl delete pod storage-inspector -n $namespace &
    wait
    echo -e "${GREEN}Storage FIO output collected${NC}"
  fi
}


extract_neo4j_logs() {
    # Get pod status and wait until Running
    podstatus=$(kubectl get pod neo4j-inspector -n $namespace -o jsonpath='{.status.phase}')
    retry=0
    until [[ $podstatus = 'Running' || $retry -gt 9 ]]; do
        sleep 1
        podstatus=$(kubectl get pod neo4j-inspector -n $namespace -o jsonpath='{.status.phase}')
        echo "Waiting for neo4j-inspector pod to start..."
        retry=$((retry+1))
        echo "Retrying... Current state: $podstatus  Retries: $retry"
    done

    if [ $retry -gt 9 ]; then
        echo "Unable to determine neo4j-inspector pod state, cannot connect to copy logs"
    else
        echo "Copying logs..."
        # Verify the existence of the logs directory
        kubectl exec -n $namespace neo4j-inspector -- ls /pvc/logs &>/dev/null
        dir_status=$?
        if [ $dir_status -ne 0 ]; then
            echo "Error: Directory /pvc/logs does not exist in neo4j-inspector pod." >&2
        else
            # Run cp command in background with & and wait for it to finish before deleting pod
            kubectl cp $namespace/neo4j-inspector:pvc/logs/ ./neo4j_loadgenerator_logs &
        fi
        wait
        echo "Deleting neo4j inspector pod..."
        kubectl delete pod neo4j-inspector -n $namespace &
        wait
        echo -e "${GREEN}Neo4j load generator logs collected${NC}"

    fi
}

gather_pvc_logs() {
  echo "Spinning up pvc inspector pod..."
  kubectl apply -f $scriptpath/pvc-inspector.yaml -n $namespace
  echo "Gathering neo4j load generator logs"
  extract_neo4j_logs
  echo "Gathering FIO output"
  extract_storage_logs
}


describe_error_pods() {
  benchmarks=( `kubectl get pods -n $namespace | grep Error | awk '{print $1}' | grep -v '^NAME'` )

  for name in "${benchmarks[@]}"
  do
    echo "Describing pod ${name}"
    kubectl describe pods -n $namespace ${name} >> "describe-${name}".txt
  done
  echo -e "${GREEN}Output of describe pods collected for Error pods${NC}"
}


describe_imagepullbackoff_pods() {
  benchmarks=( `kubectl get pods -n $namespace | grep Init:ImagePullBackOff | awk '{print $1}' | grep -v '^NAME'` )

  for name in "${benchmarks[@]}"
  do
    echo "Describing pod ${name}"
    kubectl describe pods -n $namespace ${name} >> "describe-${name}".txt
  done
  echo -e "${GREEN}Output of describe pods collected for Init:ImagePullBackOff pods${NC}"
}


describe_init_pods() {
  benchmarks=( `kubectl get pods -n $namespace | grep Init | awk '{print $1}' | grep -v '^NAME'` )

  for name in "${benchmarks[@]}"
  do
    echo "Describing pod ${name}"
    kubectl describe pods -n $namespace ${name} >> "describe-${name}".txt
  done
  echo -e "${GREEN}Output of describe pods collected for pods stuck in Init state${NC}"
}


describe_pending_pods() {
  benchmarks=( `kubectl get pods -n $namespace | grep Pending | awk '{print $1}' | grep -v '^NAME'` )

  for name in "${benchmarks[@]}"
  do
    echo "Describing pod ${name}"
    kubectl describe pods -n $namespace ${name} >> "describe-${name}".txt
  done
  echo -e "${GREEN}Output of describe pods collected for pods in Pending state${NC}"
}


get_pods() {
  echo "Saving kubectl get pods to getpods.txt..."
  kubectl get pods -n $namespace >> getpods.txt
  echo -e "${GREEN}Output of kubectl get pods saved${NC}"
}


get_pv() {
  echo "Saving kubectl get pv to pv.txt..."
  kubectl get pv -n $namespace >> pv.txt
  echo -e "${GREEN}Output of kubectl get pv saved${NC}"
}


get_pvc() {
  echo "Saving kubectl get pvc to pvc.txt..."
  kubectl get pvc -n $namespace >> pvc.txt
  echo -e "${GREEN}Output of kubectl get pvc saved${NC}"
}


save_webpage() {
  echo "Saving html report"
  echo "Port forwarding 8081..."
  #run kubectl port forward but push it to background using & so we can run the wget command
  kubectl port-forward svc/eric-oss-cn-infra-verification-tool 8081:8080 -n $namespace &
  #give it some time to make the connection
  sleep 5
  #capture the PID of kubectl so we can return to the background process later to kill it
  PID=$!
  wget -q -p http://127.0.0.1:8081 -nH -nd -Phtml
  #wait for 2 seconds
  sleep 2
  #kill it
  kill $PID
  #give it some more time to finish up before proceeding
  sleep 5
  echo "Port fowarding stopped"
  cd html
  echo "Cleaning up html..."
  #replace the 10 second refresh code as this is useless when report is not running live
  sed -i 's/<meta http-equiv=.*/ /' 'index.html'
  #update the path to css files to local directory to preserve report formatting
  sed -i 's|<link rel="stylesheet" href="\./templates/assets/css/assets\.css".*|<link rel="stylesheet" href="\./assets\.css" type="text/css"/>|' 'index.html'
  sed -i 's|<link rel="stylesheet" href="\./templates/assets/css/style\.css".*|<link rel="stylesheet" href="\./style\.css" type="text/css"/>|' 'index.html'
  cd ..
  echo -e "${GREEN}HTML report saved${NC}"
}


zip_logs() {
  echo "Zipping log files..."
  cd ..
  zip -r logs.zip logs/
  if [ "$?" -ne 127 ]; then
    echo -e "${GREEN}Log files zipped${NC}"
  else
    echo -e "${RED}Zip is not installed. Run${NC} sudo apt install zip ${RED}to install it${NC}"
  fi
}


test_namespace() {
  benchmarks=( `kubectl get pods -n $namespace | awk '{print $1}' | grep -v '^NAME'` )
  if [[ ${#benchmarks} -le 1 ]]; then
    echo "No pods running in the $namespace namespace to gather logs from"
    exit 1
  fi
}


get_valuesyaml() {
  # if we're in another dir here then relaive paths wont work... might need to save pwd and jump to that dir agiain to catch these? but then . is no good, . shoudl be bcahged to outputfile/logs
  echo "Copying values.yaml files to /logs..."
  if [ -f "${globalpath}" ]; then
    cp ${globalpath} .
        echo -e "${GREEN}eric-cniv-enm-global-values.yaml copied${NC}"
  else
    echo -e "${RED}Error: eric-cniv-enm-global-values.yaml not found${NC}"
  fi
  if [ -f "${smallpath}" ]; then
    cp ${smallpath} .
    echo -e "${GREEN}eric-cniv-enm-integration-small-production-values.yaml copied${NC}"
  else
    echo -e "${RED}Error: eric-cniv-enm-integration-small-production-values.yaml not found${NC}"
  fi
  if [ -f "${xlpath}" ]; then
    cp ${xlpath} .
    echo -e "${GREEN}eric-cniv-enm-integration-large-production-values.yaml copied${NC}"
  else
    echo -e "${RED}Error: eric-cniv-enm-integration-extra-large-production-values.yaml not found${NC}"
  fi
}


#-------------------------------------------------------------------------
#       Main
#-------------------------------------------------------------------------

while getopts ':n:o:hzv' OPTION; do

  case "$OPTION" in
    n)
      namespace="$OPTARG"
      test_namespace;
      echo "Logs will be collected for pods running in the ${namespace} namespace"
      sleep 2
      ;;

    o)
      OUTPUTFILE="$OPTARG"
      if [ -d $OUTPUTFILE ]; then
        cd $OUTPUTFILE
        echo "Logs will be saved to: $OUTPUTFILE\logs"
        sleep 2
      else
        echo "Location $OUTPUTFILE does not exist"
        exit 1
      fi
      ;;

    h)
      htmlonly=true
      ;;

    z)
      zip=true
      ;;

    v)
      valuesyaml=true
          ;;

    ?)
      echo "Usage: $(basename $0) [-n namespace] [-o outputfile] [-h] [-z] [-v]

      Available options:

      -?    Print this help and exit
      -n    Specify the namespace
      -o    Specify the output location of logs
      -h    Get the html report only and exit
      -z    Zip the logs when complete
      -v    Include the values.yaml files in the output"

      exit 1
      ;;
  esac

done
shift "$(($OPTIND -1))"


mkdir logs
cd logs

if [ "$htmlonly" = true ]; then
  save_webpage;
else
  get_pods;
  get_pv;
  get_pvc;
  gather_all_logs;
  gather_pvc_logs;
  describe_init_pods;
  describe_pending_pods;
  describe_error_pods;
  save_webpage;

  if [ "$valuesyaml" = true ]; then
    get_valuesyaml;
  fi

  if [ "$zip" = true ]; then
    zip_logs;
  fi
fi


echo -e "${LIGHTGREEN}All done! ${NC}"
exit 1
