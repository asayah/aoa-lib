#!/bin/bash
#set -e


############################################################
# Defaults
environment_overlay=base
install_infra=false
############################################################


############################################################
# Help                                                     #
############################################################
help()
{
   # Display Help
   echo "AoA installer."
   echo
   echo "Syntax: ./deploy [-f|-o|-i|-h]"
   echo "options:"
   echo "-f     path to AoA files"
   echo "-o     overlay"   
   echo "-i     install infra"
   echo "-h     print help"
   echo
}

precheck()
{

echo "##########################"
echo "    AoA Lib - Precheck    "
echo "Environemnt: $env"
echo "Install infra: $install_infra"
echo "Overlay: $environment_overlay"
echo "##########################"
echo ""
echo "Continue? [Y/N]"

read should_continue
if [[ ${should_continue} != "Y" ]]
  then
   exit 0
fi
   
}


check_env()
{
  if [[ ${env} == "" ]] || [ ! -d "$env" ]
  then
    # provide vars file
    echo "Error: env folder not found, please use -f to choose a valid env folder."
    help
    exit 1
   fi 
}

install_infra()
{
   check_env
   export install_infra=true
}


############################################################
# Get the options
while getopts "hif:o:" option; do
   case $option in
      h) # display Help
         help
         exit;;
      f) # env
         env=${OPTARG};;
      i) # infra
         install_infra;;
      o) # overlay
         environment_overlay=${OPTARG};;
     \?) # Invalid option
         echo "Error: Invalid option"
         help
         exit;;
   esac
done

check_env
precheck

export SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

cd $env
git_root="$(git rev-parse --show-toplevel)/"
export env_path=$(echo $PWD | sed -e "s+$git_root++g")

# source vars.env 
source vars.env && export $(sed '/^#/d' vars.env | cut -d= -f1)

#TODO: this should be in a init phase
# check to see if defined contexts exist
if [[ $(kubectl config get-contexts | grep ${cluster_context}) == "" ]] ; then
  echo "Check Failed: ${cluster_context} context does not exist. Please check to see if you have the clusters available"
  echo "Run 'kubectl config get-contexts' to see currently available contexts. If the clusters are available, please make sure that they are named correctly. Default is ${cluster_context}"
  exit 1;
fi

# check to see if environment overlay variable was passed through, if not prompt for it
if [[ ${environment_overlay} == "" ]]
  then
    # provide environment overlay
    echo "Please provide the environment overlay to use (i.e. prod, dev):"
    read environment_overlay
fi

# install argocd
#TODO: refactor the install-argocd.sh to no relay on cd
cd $SCRIPT_DIR/bootstrap-argocd
if [ "${environment_overlay}" == "ocp" ] ; then 
     $SCRIPT_DIR/bootstrap-argocd/install-argocd.sh insecure-rootpath-ocp ${cluster_context}
  else
     $SCRIPT_DIR/bootstrap-argocd/install-argocd.sh insecure-rootpath ${cluster_context}
  fi

# wait for argo cluster rollout
$SCRIPT_DIR/tools/wait-for-rollout.sh deployment argocd-server argocd 20 ${cluster_context}

cd $env
# deploy app of app waves
for i in $(ls | sort -n); do 
  echo "starting ${i}"
  # run init script if it exists
  [[ -f "${i}/init.sh" ]] && ${i}/init.sh 
  # deploy aoa wave
  $SCRIPT_DIR/tools/configure-wave.sh ${env_path} ${i} ${environment_overlay} ${cluster_context} ${github_username} ${repo_name} ${target_branch}
  # run test script if it exists
  [[ -f "${i}/test.sh" ]] && ${i}/test.sh
done

echo "END."

