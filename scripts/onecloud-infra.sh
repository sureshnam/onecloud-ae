#!/bin/bash -ex
#
# Copyright 2016-2022 Intel Corporation
# Copyright 2016-2022 Habana Corporation
# All Rights Reserved.
#
# Unauthorized copying of this file, via any medium is strictly prohibited.
# Proprietary and confidential.
#
# Maintainer: Aung Oo aka Mike <aung.san.oo@intel.com>
#
# This scripts will run inside VM. Need to export jenkins env to vm.
#

#set -x
#set -e

OneCloud_Report_Channel="https://habanalabs.webhook.office.com/webhookb2/00072444-e850-451d-b045-03eafea537bb@0d4d4539-213c-4ed8-a251-dc9766ba127a/JenkinsCI/03278befab4d40c1878b26a8694a9e4e/554ad977-aa4a-4900-85ff-e635fae3833d"

export TERM=xterm-256color

echo -e "OneCloud DevOps" | boxes -d stone -a hcvcjc -p a2v0 -s 80

if [[ -z "${NEW_USER}" || "${NEW_USER}" == "" ]]; then
  export BUILD_NUMBER=1
  export NEW_USER=asanoo
fi


if [[ -z "${pid_reboot_threshold}" || "${pid_reboot_threshold}" == "" ]]; then
  #export pid_reboot_threshold=1000  # dev
  export pid_reboot_threshold=4000000
fi


echo ""
echo "BUILD_NUMBER=${BUILD_NUMBER}"
echo ""

echo "DOMAIN=${DOMAIN}"
echo "NEW_USER=${NEW_USER}"
echo ""

echo "RESERVE_SERVER=${RESERVE_SERVER}"
echo "AllocationTime=${AllocationTime}"
echo ""

if [ -f ./USER_INFO_${BUILD_NUMBER}.txt ]; then
  source ./USER_INFO_${BUILD_NUMBER}.txt
fi


install_dependencies() {

  sudo apt update

  sudo apt install -y --no-install-recommends htop iotop iftop byobu nano wget curl rsync openjdk-11-jdk nfs-common lvm2 gdisk
  sudo apt install -y --no-install-recommends qemu-kvm libvirt-clients libvirt-daemon-system virt-manager qemu-utils cpu-checker
  sudo apt install -y --no-install-recommends boxes dnsmasq net-tools

}


export ONECLOUD_REPO_USER_NAME=""

export ONECLOUD_REPO_SERVER="artifactory-oc.amr.corp.intel.com"
export ONECLOUD_REPO_PATH="artifactory/repo"

export AE_AUTOMATION_REPO_NAME="onecloud-ae"
export AE_Automation_Branch="master"

export CD_RELEASE_REPO_NAME="onecloud-ae-automation"
export CD_RELEASE_Branch="cd_release"


if [[ -z "${RELEASE_VERSION}" || "${RELEASE_VERSION}" == "" ]]; then
  export RELEASE_VERSION="1.14.0"
fi

if [[ -z "${RELEASE_BUILD_ID}" || "${RELEASE_BUILD_ID}" == "" ]]; then
  export RELEASE_BUILD_ID="493"
fi

echo "RELEASE_VERSION: ${RELEASE_VERSION}"
echo "RELEASE_BUILD_ID: ${RELEASE_BUILD_ID}"


export __internal=""
# only for ubuntu now
export HL_PKG_CMD="apt-get"
export __deb_separator="-"


checkoutAEAutomation() {

  echo ""
  echo -e "checkoutAEAutomation" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  ssh-keyscan ${ONECLOUD_REPO_SERVER} >> $HOME/.ssh/known_hosts && \
  sudo rm -rf ./${AE_AUTOMATION_REPO_NAME} 2>&1 | tee /dev/null && \
  time git clone -b ${AE_Automation_Branch} --single-branch ssh://${ONECLOUD_REPO_SERVER}:/${ONECLOUD_REPO_PATH}/${AE_AUTOMATION_REPO_NAME}.git && \
  ls -haltr ./ && \
  ls -haltr ./${AE_AUTOMATION_REPO_NAME} && \
  cd ./${AE_AUTOMATION_REPO_NAME} && \
  git log -n 3 && cd - && \
  echo ""

}


checkout_cd_release() {

  echo ""
  echo -e "checkout_cd_release" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  ssh-keyscan ${ONECLOUD_REPO_SERVER} >> $HOME/.ssh/known_hosts && \
  sudo rm -rf ./${CD_RELEASE_REPO_NAME} 2>&1 | tee /dev/null && \
  time git clone -b ${CD_RELEASE_Branch} --single-branch ssh://${ONECLOUD_REPO_SERVER}:/${ONECLOUD_REPO_PATH}/${CD_RELEASE_REPO_NAME}.git && \
  ls -haltr ./ && \
  ls -haltr ./${CD_RELEASE_REPO_NAME} && \
  cd ./${CD_RELEASE_REPO_NAME} && \
  git log -n 3 && cd - && \
  echo ""

}


# save_env

save_env() {

  echo "saving env to ${WORKSPACE}/env"
  echo ""

  if [ -f ${WORKSPACE}/env ]; then
    rm ${WORKSPACE}/env 2>&1 | tee /dev/null
  fi

  echo "export reservationStartTime='${reservationStartTime}'" >> ${WORKSPACE}/env
  echo "export reservationStartDateTimeString='${reservationStartDateTimeString}'" >> ${WORKSPACE}/env
  echo "" >> ${WORKSPACE}/env

  echo "export WORKSPACE=${WORKSPACE}" >> ${WORKSPACE}/env
  echo "export JOB_BASE_NAME=${JOB_BASE_NAME}" >> ${WORKSPACE}/env
  echo "export BUILD_NUMBER=${BUILD_NUMBER}" >> ${WORKSPACE}/env
  echo "export Reservation_Type=${Reservation_Type}" >> ${WORKSPACE}/env
  echo "" >> ${WORKSPACE}/env

  echo "export DOMAIN=${DOMAIN}" >> ${WORKSPACE}/env
  echo "export NEW_USER=${NEW_USER}" >> ${WORKSPACE}/env
  echo "" >> ${WORKSPACE}/env

  echo "export SSH_KEY=\"${SSH_KEY}\"" >> ${WORKSPACE}/env
  echo "" >> ${WORKSPACE}/env

  echo "export RESERVE_SERVER=${RESERVE_SERVER}" >> ${WORKSPACE}/env
  echo "export AllocationTime=${AllocationTime}" >> ${WORKSPACE}/env
  echo "" >> ${WORKSPACE}/env

}

# user account


create_user_account_authorized_keys() {

  echo "create_user_account_authorized_keys for ${DOMAIN}\\${NEW_USER}"
  echo ""

  echo -e "Creating User Folder and authorized_keys. It could take as long as 5 mins *" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  # GER / GAR / AMR
  if [[ "${DOMAIN}" != "" && "${NEW_USER}" != "" ]]; then

    current_time=$(date "+%Y.%m.%d-%H.%M.%S")
    echo "current_time=${current_time}"

    fgrep "${DOMAIN}\\${NEW_USER}" /etc/opt/quest/vas/users.allow && UESR_FOUND=0 || UESR_FOUND=1
    #UESR_FOUND=$?
    echo "UESR_FOUND=${UESR_FOUND}"
    echo ""

    if [[ "${UESR_FOUND}" != "0" ]]; then

      mkdir -p ~/vas_bkp
      sudo cp /etc/opt/quest/vas/users.allow ~/vas_bkp/users.allow_${current_time}
      sudo cat /etc/opt/quest/vas/users.allow

      cat << EOF | sudo tee -a /etc/opt/quest/vas/users.allow
${DOMAIN}\\${NEW_USER}
EOF

      echo ""
      sudo cat /etc/opt/quest/vas/users.allow
      echo ""

      time sudo vastool flush

    fi

    ls -la /home/
    echo ""

    sudo vastool status 2>&1 | tee /dev/null
    VAS_STATUS=$?
    echo "VAS_STATUS=${VAS_STATUS}"
    echo ""

    if [[ "${VAS_STATUS}" == "0" ]]; then

      new_user_home="/home/${NEW_USER}"
      new_user_id=$(id -u ${NEW_USER})
      new_user_group_id=$(id -g ${NEW_USER})
      #new_user_name=$(sudo ls -la /home/${NEW_USER}/.ssh/authorized_keys | awk -F' '  '{print $3}')
      #new_user_group_name=$(sudo ls -la /home/${NEW_USER}/.ssh/authorized_keys | awk -F' '  '{print $4}')

      echo "new_user_home=${new_user_home}"
      #echo "new_user_name=${NEW_USER}"
      #echo "new_user_group_name=${new_user_group_name}"
      echo ""

      sudo mkdir -p ${new_user_home}/.ssh

      cat << EOF | sudo tee -a ${new_user_home}/.ssh/authorized_keys

${SSH_KEY}

EOF

      #echo "# Virtual Environment Wrapper" >> ${new_user_home}/.ssh/authorized_keys

      sudo chown -R ${new_user_id}.${new_user_group_id} ${new_user_home}
      sudo chmod 744 ${new_user_home}/.ssh
      sudo chmod 600 ${new_user_home}/.ssh/authorized_keys
      echo ""

      sudo ls -la ${new_user_home}/
      echo ""

      sudo ls -la ${new_user_home}/.ssh/
      echo ""

      sudo cat ${new_user_home}/.ssh/authorized_keys
      echo ""

    fi
  else
    echo "${DOMAIN} && ${NEW_USER} is empty"
  fi

}


get_user_account_info() {

  echo ""
  echo "get_user_account_info"
  echo ""

  #ssh-keyscan reserve-hf-2.amr.corp.intel.com >> $HOME/.ssh/known_hosts

  RESERVE_SERVER=$(hostname -A | cut -d ' ' -f1)
  echo "RESERVE_SERVER=${RESERVE_SERVER}"
  echo ""

  echo "export RESERVE_SERVER=${RESERVE_SERVER}" >> ${WORKSPACE}/env

  #ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@reserve-hf-2.amr.corp.intel.com  "mkdir -p ${WORKSPACE}"
  ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no  ubuntu@100.83.160.55 "sudo mkdir -p ${WORKSPACE}"
  
  scp -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ${WORKSPACE}/env  ae-jenkins@reserve-hf-2.amr.corp.intel.com:${WORKSPACE}/${BUILD_NUMBER}.env
  scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no  ${WORKSPACE}/env ubuntu@100.83.160.55:${WORKSPACE}/${BUILD_NUMBER}.env 
  
  scp -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ${WORKSPACE}/${AE_AUTOMATION_REPO_NAME}/scripts/onecloud-infra.sh  ae-jenkins@reserve-hf-2.amr.corp.intel.com:${WORKSPACE}/
  scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no  ${WORKSPACE}/${AE_AUTOMATION_REPO_NAME}/scripts/onecloud-infra.sh ubuntu@100.83.160.55:${WORKSPACE}/ 

  ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@reserve-hf-2.amr.corp.intel.com  "source ${WORKSPACE}/${BUILD_NUMBER}.env && source ${WORKSPACE}/onecloud-infra.sh && save_user_account_info && rm ${WORKSPACE}/${BUILD_NUMBER}.env"
  ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no  ubuntu@100.83.160.55 "source ${WORKSPACE}/${BUILD_NUMBER}.env && source ${WORKSPACE}/onecloud-infra.sh && save_user_account_info && rm ${WORKSPACE}/${BUILD_NUMBER}.env"
  echo ""

  scp -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@reserve-hf-2.amr.corp.intel.com:/${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.txt  ${WORKSPACE}/
  scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no  ubuntu@100.83.160.55:${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.txt  ${WORKSPACE}/ 
  echo ""

  # scp .profile and .bashrc if necessary

  echo "USER_INFO"
  cat ./USER_INFO_${BUILD_NUMBER}.txt
  echo ""

  scp -i ~/.ssh/id_rsa-reserve-hf-2  ae-jenkins@reserve-hf-2.amr.corp.intel.com:${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.authorized_keys  ${WORKSPACE}/
  scp -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no  ubuntu@100.83.160.55:${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.authorized_keys  ${WORKSPACE}/ 
  echo ""

  cat ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.authorized_keys
  echo ""

}


save_user_account_info() {

  echo ""
  echo "save_user_account_info"
  echo ""

  mkdir -p ${WORKSPACE}
  rm -f ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.txt
  touch ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.txt

  new_user_name=$(sudo ls -la /home/${NEW_USER}/.ssh/authorized_keys | awk -F' '  '{print $3}')
  new_user_group_name=$(sudo ls -la /home/${NEW_USER}/.ssh/authorized_keys | awk -F' '  '{print $4}')
  echo "" | tee -a ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.txt
  echo "new_user_name=${new_user_name}" | tee -a ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.txt
  echo "new_user_group_name=${new_user_group_name}" | tee -a ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.txt

  new_user_id=$(id -u ${NEW_USER})
  new_user_group_id=$(id -g ${NEW_USER})
  echo "" | tee -a ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.txt
  echo "new_user_id=${new_user_id}" | tee -a ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.txt
  echo "new_user_group_id=${new_user_group_id}" | tee -a ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.txt
  echo ""

  echo "${WORKSPACE}/"
  ls -la ${WORKSPACE}/
  echo ""

  echo "${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.txt"
  echo ""

  cat ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.txt
  echo ""

  sudo cp /home/${NEW_USER}/.ssh/authorized_keys  ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.authorized_keys
  sudo chown `id -u`.`id -g` ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.authorized_keys

}


#sudo groupadd -g ${NEW_GID} "Software-SG" 2>&1 | tee /dev/null

#sudo useradd -u ${NEW_UID} -g ${NEW_GID} -d "/storage/${NEW_USER_NAME}" -G sudo -s /bin/bash $NEW_USER_NAME -p "$(openssl passwd -1 Hab@12345)"


create_user_account() {

  if [ -f ./USER_INFO_${BUILD_NUMBER}.txt ]; then

    source ./USER_INFO_${BUILD_NUMBER}.txt

    # tmp hard-coded
    new_user_group_name="intelall"

    # group

    getent group ${new_user_group_id} && NEW_USER_GRP_EXISTS_RC=0 || NEW_USER_GRP_EXISTS_RC=1
    echo "NEW_USER_GRP_EXISTS_RC=${NEW_USER_GRP_EXISTS_RC}"
    echo ""

    if [[ ${NEW_USER_GRP_EXISTS_RC} == 1 ]]; then
      # creates a new group account
      sudo groupadd -g ${new_user_group_id} ${new_user_group_name}
    fi
    # else
    #   -g, –gid GID: The group ID of the given GROUP will be changed to GID.
    #   sudo groupmod -g ${new_user_group_id} ${new_user_group_name}
    # fi

    # user

    new_user_home="/home/${NEW_USER}"

    # check useraccount first
    id ${NEW_USER} && NEW_USER_ACC_EXISTS_RC=0 || NEW_USER_ACC_EXISTS_RC=1
    echo "NEW_USER_ACC_EXISTS_RC=${NEW_USER_ACC_EXISTS_RC}"
    echo ""

    if [[ ${NEW_USER_ACC_EXISTS_RC} == 1 ]]; then

      echo "Create User Account ${NEW_USER} -u ${new_user_id} -g ${new_user_group_id} -m -d ${new_user_home} -G ${new_user_group_name}"
      sudo useradd -u ${new_user_id} -g ${new_user_group_id} -m -d ${new_user_home} -G ${new_user_group_name} -s /bin/bash ${NEW_USER} -p "$(openssl passwd -1 ${new_user_id}_${new_user_group_id})"
      sudo chown ${new_user_id}.${new_user_group_id} ${new_user_home}

      # sudo rsync -arPhv ~/.profile  ${new_user_home}/
      # sudo rsync -arPhv ~/.bashrc   ${new_user_home}/

      # sudo chown -R ${new_user_id}.${new_user_group_id} ${new_user_home}/.profile
      # sudo chown -R ${new_user_id}.${new_user_group_id} ${new_user_home}/.bashrc

      # sudo chmod 644 ${new_user_home}/.profile 2>&1 | tee /dev/null
      # sudo chmod 644 ${new_user_home}/.bashrc 2>&1 | tee /dev/null

    else
      sudo usermod -u ${new_user_id} ${NEW_USER}
    fi
    echo "Create User Account ${NEW_USER} created."

    sudo echo "${NEW_USER}    ALL=NOPASSWD:ALL,!SU,!PASSWD,!VISUDO,!SUDOERS,!CH,!APT,!CAT,!EDITOR,!REBOOT,!TOOLS,!RM,!USERMOD,!GROUPMOD" | sudo tee -a /etc/sudoers

    sudo usermod -aG docker ${NEW_USER} 2>&1 | tee /dev/null
    sudo usermod -aG devcloud ${NEW_USER} 2>&1 | tee /dev/null
    sudo usermod -aG libvirt ${NEW_USER} 2>&1 | tee /dev/null
    sudo usermod --append --groups libvirt ${NEW_USER} 2>&1 | tee /dev/null

    sudo mkdir -p ${new_user_home}/.ssh
    sudo ls -la ${new_user_home}

    echo "Update user ${NEW_USER} authorized_keys"
    sudo cp ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.authorized_keys ${new_user_home}/.ssh/authorized_keys

    sudo chown -R ${new_user_id}.${new_user_group_id} ${new_user_home}
    sudo chmod 744 ${new_user_home}/.ssh

    sudo chmod 600 ${new_user_home}/.ssh/* 2>&1 | tee /dev/null

    sudo ls -la ${new_user_home}
    echo ""

    echo "Check ${NEW_USER} group"
    getent group | grep ${NEW_USER}
    echo ""

    # nfs_home_${NEW_USER}
    sudo mkdir -p /devops
    sudo umount /devops 2>&1 | tee /dev/null
    sudo mount -t nfs -o vers=3,timeo=10 HF2COREBAEDEVCLOUD-DM.cps.intel.com:/fs_HF2AEDEVCLOUD_HOME  /devops  2>&1 | tee /dev/null
    sudo mkdir -p /devops/${NEW_USER}
    sudo chown ${new_user_id}.${new_user_group_id} /devops/${NEW_USER}

    sudo mkdir -p /nfs_home_${NEW_USER}
    sudo umount /nfs_home_${NEW_USER} 2>&1 | tee /dev/null
    sudo chown ${new_user_id}.${new_user_group_id} /nfs_home_${NEW_USER}

    sudo mount --bind /devops/${NEW_USER} /nfs_home_${NEW_USER}
    sudo chown ${new_user_id}.${new_user_group_id} /nfs_home_${NEW_USER}

    # add to /etc/fstab
    echo "add to /etc/fstab"
    echo "/devops/${NEW_USER}     /nfs_home_${NEW_USER}    none  defaults,rw,bind,x-systemd.after=/devops  0  0" | sudo tee -a /etc/fstab

    echo ""

    df -h
    echo ""

  else
    echo "./USER_INFO_${BUILD_NUMBER}.txt NOT FOUND."
  fi

}


lock_user() {

  echo "lock user ${NEW_USER}"
  echo ""

  sudo grep "${NEW_USER}" /var/log/auth.log | tail -n 21
  echo ""

  echo "lock ${NEW_USER} account"
  sudo usermod -L -e 1 ${NEW_USER} 2>&1 | tee /dev/null

  sudo sed -i "/${NEW_USER}/d" /etc/sudoers 2>&1 | tee /dev/null

  # remove fstab mount entry
  sudo sed -i "/nfs_home_${NEW_USER}/d" /etc/fstab

} # lock_user


unlock_user() {

  echo "unlock user ${NEW_USER}"
  echo ""

  if [[ ! -z "${NEW_USER}" && "${NEW_USER}" != "" ]]; then
    echo "unlock ${NEW_USER} account"
    sudo chage -E -1 "${NEW_USER}" 2>&1 | tee /dev/null
    #sudo usermod -U -e "${NEW_USER}" 2>&1 | tee /dev/null
  fi

} # unlock_user


# end user account


#

show_installed_habana() {

  echo ""
  echo "show_installed_habana"
  echo ""

  distributor=$(lsb_release -is)
  echo "distributor=${distributor}"

  if [ "${distributor}" == "Ubuntu" ]; then
    sudo apt list --installed | grep habana 2>&1 | tee /dev/null
  fi

}


print_all_version() {

  echo ""
  echo "print_all_version"
  echo ""

  show_installed_habana
  echo ""

  show_h_pci_devices
  echo ""

  echo "Check card with hl-smi"
  sudo hl-smi 2>&1 | tee /dev/null
  echo ""

  sudo hl-smi -q 2>/dev/null | head -n 88
  echo ""

  docker version
  echo ""

}


print-cpu-performance() {

  echo "scaling_governor"
  sudo cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>&1 | tee /dev/null
  sudo cat /sys/devices/system/cpu/cpu$((`nproc` - 1))/cpufreq/scaling_governor 2>&1 | tee /dev/null
  echo ""

  echo "energy_perf_bias"
  sudo cat /sys/devices/system/cpu/cpu0/power/energy_perf_bias 2>&1 | tee /dev/null
  sudo cat /sys/devices/system/cpu/cpu$((`nproc` - 1))/power/energy_perf_bias 2>&1 | tee /dev/null
  echo ""

  echo "/etc/default/cpufrequtils"
  sudo cat /etc/default/cpufrequtils 2>&1 | tee /dev/null
  echo ""

  echo "/proc/cpuinfo"
  cat /proc/cpuinfo | grep -i mhz
  echo ""

}


#

# --Habana Labs

show_h_pci_devices() {

  echo ""
  echo "show_h_pci_devices"
  echo ""

  lspci -nnk -d "1da3:"
  echo ""

}


remove_habanalabs_mod() {

  # check driver modules exist
  # ls -l /lib/modules/$(uname -r)/updates/dkms/habanalabs.ko
  # ls -l /lib/modules/$(uname -r)/updates/dkms/habanalabs_en.ko

  lsmod | grep habanalabs 2>&1 | tee /dev/null
  echo ""

  modprobe --show-depends habanalabs
  echo ""

  echo "rmmod habanalabs" && \
  time sudo rmmod habanalabs 2>&1 | tee /dev/null
  echo "rmmod habanalabs_cn" && \
  time sudo rmmod habanalabs_cn 2>&1 | tee /dev/null
  echo "rmmod habanalabs_ib" && \
  time sudo rmmod habanalabs_ib 2>&1 | tee /dev/null
  echo "rmmod habanalabs_en" && \
  time sudo rmmod habanalabs_en 2>&1 | tee /dev/null

  echo "Check mod habanalabs"
  mod_habanalabs=$(lsmod | grep habanalabs | wc -l)
  echo "mod_habanalabs: ${mod_habanalabs}"

  if [[ "${mod_habanalabs}" -gt 0 ]]; then
    echo "rmmod habanalabs fail."
  fi
  echo ""

}


modprobe_habanalabs() {

  modprobe --show-depends habanalabs
  echo ""

  echo "modprobe habanalabs_ib" && \
  time sudo modprobe habanalabs_ib 2>&1 | tee /dev/null
  echo "modprobe habanalabs_cn" && \
  time sudo modprobe habanalabs_cn 2>&1 | tee /dev/null
  echo "modprobe habanalabs" && \
  time sudo modprobe habanalabs

  lsmod | grep habanalabs
  echo ""

}


npu_nic_up() {

  if [ ! -d "/tmp_data/automation" ]; then
    CheckoutAutomation
  fi

  cd /tmp_data/automation/habana_scripts

  ./manage_network_ifs.sh --status

  ./manage_network_ifs.sh --up
  sleep 7
  ./manage_network_ifs.sh --status

}


npu_nic_status() {

  if [ ! -d "/tmp_data/automation" ]; then
    CheckoutAutomation
  fi

  cd /tmp_data/automation/habana_scripts

  ./manage_network_ifs.sh --status

}


load_habana_driver() {

  echo ""
  echo "load_habana_driver"
  echo ""

  lspci -nnk -d "1da3:"
  echo ""

  gaudi_card_pci_devices=$(lspci | grep "Habana Labs" | awk '{print $1}')
  echo ""
  echo "gaudi_card_pci_devices=${gaudi_card_pci_devices}"
  echo ""

  #IFS=', ' read -r -a gaudi_card_pci_devices <<< "$gaudi_card_pci_devices"

  IFS=$'\n' read -rd '' -a gaudi_card_pci_devices <<<"$gaudi_card_pci_devices"
  # for i in "${gaudi_card_pci_devices[@]}"
  # do
  #   echo "gaudi_card_pci_device=$i"
  # done
  # echo ""

  echo "vfio-pci/unbind"
  echo ""

  for i in "${gaudi_card_pci_devices[@]}"
  do
    echo "0000:$i" | sudo tee /sys/bus/pci/drivers/vfio-pci/unbind 2>&1 | tee /dev/null
  done
  echo ""

  echo "Check driver_override"
  echo ""

  for i in "${gaudi_card_pci_devices[@]}"
  do
    cat /sys/bus/pci/devices/"0000:$i"/driver_override 2>&1 | tee /dev/null
  done
  echo ""

  echo "driver_override"
  echo ""

  for i in "${gaudi_card_pci_devices[@]}"
  do
    echo "habanalabs" | sudo tee /sys/bus/pci/devices/"0000:$i"/driver_override
  done
  echo ""

  echo "Check driver_override"
  echo ""

  for i in "${gaudi_card_pci_devices[@]}"
  do
    cat /sys/bus/pci/devices/"0000:$i"/driver_override
  done
  echo ""

  echo "habanalabs/bind"
  echo ""

  for i in "${gaudi_card_pci_devices[@]}"
  do
    echo "0000:$i" | sudo tee -a /sys/bus/pci/drivers/habanalabs/bind
  done
  echo ""

  lspci -nnk -d "1da3:"
  hl-smi 2>&1 | tee /dev/null

}


load_vfio_pci_driver() {

  echo ""
  echo "load_vfio_pci_driver"
  echo ""

  hl-smi
  echo ""
  echo ""

  lspci -nnk -d "1da3:"
  echo ""

  gaudi_card_pci_devices=$(lspci | grep "Habana Labs" | awk '{print $1}')
  echo ""
  echo "gaudi_card_pci_devices=${gaudi_card_pci_devices}"
  echo ""

  #IFS=', ' read -r -a gaudi_card_pci_devices <<< "$gaudi_card_pci_devices"
  IFS=$'\n' read -rd '' -a gaudi_card_pci_devices <<<"$gaudi_card_pci_devices"

  echo "habanalabs/unbind"
  echo ""

  for i in "${gaudi_card_pci_devices[@]}"
  do
    echo "0000:$i" | sudo tee /sys/bus/pci/drivers/habanalabs/unbind
  done
  echo ""

  echo "Check driver_override"
  echo ""

  for i in "${gaudi_card_pci_devices[@]}"
  do
    cat /sys/bus/pci/devices/"0000:$i"/driver_override
  done


  echo "driver_override"
  echo ""

  for i in "${gaudi_card_pci_devices[@]}"
  do
    echo "vfio-pci" | sudo tee   /sys/bus/pci/devices/"0000:$i"/driver_override
  done
  echo ""


  echo "Check driver_override"
  echo ""

  for i in "${gaudi_card_pci_devices[@]}"
  do
    cat /sys/bus/pci/devices/"0000:$i"/driver_override
  done
  echo ""

  echo "vfio-pci/bind"
  echo ""

  for i in "${gaudi_card_pci_devices[@]}"
  do
    echo "0000:$i" | sudo tee -a /sys/bus/pci/drivers/vfio-pci/bind
  done
  echo ""

  lspci -nnk -d "1da3:"
  hl-smi 2>&1 | tee /dev/null

}


card-reset-hl-fw-loader() {

  echo -e "card-reset-hl-fw-loader" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  remove-habanalabs-mod
  echo ""

  yes | sudo hl-fw-loader -rR

}


remove-habanalabs-mod() {

  echo -e "remove-habanalabs-mod" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  # check driver modules exist
  # ls -l /lib/modules/$(uname -r)/updates/dkms/habanalabs.ko
  # ls -l /lib/modules/$(uname -r)/updates/dkms/habanalabs_en.ko

  lsmod | grep habanalabs
  echo ""

  modprobe --show-depends habanalabs
  echo ""

  echo "rmmod habanalabs" && \
  time sudo rmmod habanalabs 2>&1 | tee /dev/null
  echo "rmmod habanalabs_cn" && \
  time sudo rmmod habanalabs_cn 2>&1 | tee /dev/null
  echo "rmmod habanalabs_ib" && \
  time sudo rmmod habanalabs_ib 2>&1 | tee /dev/null
  echo "rmmod habanalabs_en" && \
  time sudo rmmod habanalabs_en 2>&1 | tee /dev/null

  echo "Check mod habanalabs"
  lsmod | grep habanalabs
  echo ""

} # remove-habanalabs-mod


modprobe-habanalabs() {

  echo -e "modprobe-habanalabs" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  echo "Check mod habanalabs"
  lsmod | grep habanalabs 2>&1 | tee /dev/null
  echo ""

  echo "Run modprobe"
  time sudo modprobe habanalabs_en && \
  time sudo modprobe habanalabs_ib && \
  time sudo modprobe habanalabs_cn && \
  time sudo modprobe habanalabs
  echo "modprobe done."
  echo ""

  echo "Check mod habanalabs"
  lsmod | grep habanalabs
  echo ""

} # modprobe-habanalabs


purge-habana-package() {

  echo -e "purge-habana-package" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  remove_habanalabs_mod

  echo "/var/lib/dpkg/info/habanalabs-dkms.prerm"
  sudo cat /var/lib/dpkg/info/habanalabs-dkms.prerm
  echo ""

  sudo rm -rf /var/lib/dpkg/info/habanalabs-dkms.prerm 2>&1 | tee /dev/null
  #sudo udevadm control --reload    # /var/lib/dpkg/info/habanalabs-dkms.postinst
  # __device=$(grep PCI_ID /sys/bus/pci/devices/*/uevent | grep -i 1da3: | grep -qE '1020|1030|1060' && echo "true" || echo "false")

  echo "remove /var/lib/dpkg/info/habana*"
  sudo ls -haltr /var/lib/dpkg/info/habana* 2>&1 | tee /dev/null
  sudo rm -rf  /var/lib/dpkg/info/habana* 2>&1 | tee /dev/null


  # until build another clean VM
  sudo apt-get install -f 2>&1 | tee /dev/null
  sudo apt purge -y --allow-change-held-packages habana* 2>&1 | tee /dev/null
  sudo apt-get install -f
  sudo apt-get autoclean

  echo "purge habanalabs-* habanatools done"
  echo ""

  echo "rm habanalabs-dkms folder and hl-smi_log.txt"
  sudo rm -rf  /var/lib/dkms/habanalabs-dkms/*
  sudo rm -rf /var/log/habana_logs/hl-smi_log.txt
  sudo rm -rf /opt/habanalabs
  sudo rm -rf /usr/lib/habanalabs
  sudo rm -rf /opt/habanalabs

  sudo rm -rf /etc/habana-container-runtime/config.toml

  sudo cat /etc/modules-load.d/habanalabs.conf
  sudo rm -rf /etc/modules-load.d/habanalabs.conf

  sudo cat /etc/udev/rules.d/habana.rules 2>&1 | tee /dev/null
  sudo rm -rf /etc/udev/rules.d/habana.rules 2>&1 | tee /dev/null


  # /tmp/habanalabs-installer.sh - uninstall_base_packages
  sudo rm -rf /usr/lib/habanalabs 2>&1 | tee /dev/null
  sudo rm -rf /usr/include/habanalabs 2>&1 | tee /dev/null
  sudo rm -rf /opt/habanalabs 2>&1 | tee /dev/null

  if [ -f /etc/dracut.conf.d/habanalabs.conf ]; then
    sudo rm -rf /etc/dracut.conf.d/habanalabs.conf 2>&1 | tee /dev/null
  fi

  if [ -f /lib/systemd/system/habanalabs.service ]; then
    sudo rm -rf /etc/modprobe.d/habanalabs.conf 2>&1 | tee /dev/null
  fi

  if [ -f /lib/systemd/system/habanalabs.service ]; then
    sudo rm -rf /lib/systemd/system/habanalabs.service 2>&1 | tee /dev/null
  fi

  if [ -f /etc/rc.local ]; then
    sudo sed --in-place '/habanalabs/d' /etc/rc.local 2>&1 | tee /dev/null
  fi

  if [ -f /etc/rc.d/rc.local ]; then
    sudo sed --in-place '/habanalabs/d' /etc/rc.d/rc.local 2>&1 | tee /dev/null
  fi

  sudo rm -rf /etc/sensors.d/hl_sensors.conf 2>&1 | tee /dev/null

} # purge-habana-package


install-habana-packages() {

  echo -e "install-habana-packages" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  sudo apt-get install --reinstall -o Dpkg::Options::="--force-confnew" -y \
    habanalabs-firmware \
    habanalabs-firmware-tools \
    habanatools \
    habanalabs-dkms \
    habanalabs-thunk \
    habanalabs-graph \
    habanalabs-qual \
    habanalabs-container-runtime

  echo ""
  echo "apt-get install done."
  echo ""

  modprobe-habanalabs

  echo "" && \
  sudo hl-smi -L && \
  echo "" && \
  sudo hl-smi -q | grep Firmware
  echo "" && \
  sudo hl-smi

} # install-habana-packages


check-habana-packages-version() {

  echo ""
  echo -e "check-habana-packages-version" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  habanalabs_dkms_installed=$(sudo apt list --installed 2>/dev/null | grep -w habanalabs-dkms | cut -d ' ' -f2)
  echo "habanalabs_dkms_installed: ${habanalabs_dkms_installed}"

  if [[ "${habanalabs_dkms_installed}" != "${RELEASE_VERSION}-${RELEASE_BUILD_ID}" ]]; then
    purge-habana-package
    install-habana-packages-latest-release
  fi

}


install-habana-packages-latest-release() {

  echo ""
  echo -e "install-habana-packages-latest-release" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  # sudo -E bash hl-installer.sh 2>&1 | tee /dev/null && \
  # sudo -E bash hl-install.sh 2>&1 | tee /dev/null && \

  stop_docker

  sudo ${HL_PKG_CMD} update
  sudo ${HL_PKG_CMD} install -o Dpkg::Options::="--force-confnew" -y \
    --allow-change-held-packages \
    --allow-downgrades \
    habanatools=${RELEASE_VERSION}-${RELEASE_BUILD_ID} && \
  sudo ${HL_PKG_CMD} install -o Dpkg::Options::="--force-confnew" -y \
    --allow-change-held-packages \
    --allow-downgrades \
    habanalabs-container-runtime=${RELEASE_VERSION}-${RELEASE_BUILD_ID} && \
  sudo ${HL_PKG_CMD} install -o Dpkg::Options::="--force-confnew" -y \
    --allow-change-held-packages \
    --allow-downgrades \
    habanalabs-rdma-core=${RELEASE_VERSION}-${RELEASE_BUILD_ID} && \
  sudo ${HL_PKG_CMD} install -o Dpkg::Options::="--force-confnew" -y \
    --allow-change-held-packages \
    --allow-downgrades \
    habanalabs-dkms${__internal}=${RELEASE_VERSION}${__deb_separator}${RELEASE_BUILD_ID} && \
  sudo ${HL_PKG_CMD} install -o Dpkg::Options::="--force-confnew" -y \
    --allow-change-held-packages \
    --allow-downgrades \
    habanalabs-thunk${__internal}=${RELEASE_VERSION}-${RELEASE_BUILD_ID} && \
  sudo ${HL_PKG_CMD} install -o Dpkg::Options::="--force-confnew" -y \
    --allow-change-held-packages \
    --allow-downgrades \
    habanalabs-firmware-tools=${RELEASE_VERSION}-${RELEASE_BUILD_ID} && \
  sudo ${HL_PKG_CMD} install -o Dpkg::Options::="--force-confnew" -y \
    --allow-change-held-packages \
    --allow-downgrades \
    habanalabs-graph${__internal}=${RELEASE_VERSION}-${RELEASE_BUILD_ID} && \
  sudo ${HL_PKG_CMD} install -o Dpkg::Options::="--force-confnew" -y \
    --allow-change-held-packages \
    --allow-downgrades \
    habanatools=${RELEASE_VERSION}-${RELEASE_BUILD_ID} && \
  sudo ${HL_PKG_CMD} install -o Dpkg::Options::="--force-confnew" -y \
    --allow-change-held-packages \
    --allow-downgrades \
    habanalabs-qual${__internal}=${RELEASE_VERSION}-${RELEASE_BUILD_ID}

  echo ""
  echo "habana-packages-latest-release installation done."
  echo ""

  sudo apt-mark hold habanatools habanalabs-container-runtime habanalabs-rdma-core habanalabs-dkms habanalabs-thunk habanalabs-firmware-tools habanalabs-graph habanatools habanalabs-qual

  sudo apt-mark hold habanalabs-sw-tools 2>&1 | tee /dev/null

  sudo apt-mark hold habanalabs-firmware 2>&1 | tee /dev/null
  sudo apt-mark hold habanalabs-firmware-odm 2>&1 | tee /dev/null

  modprobe-habanalabs

  echo "" && \
  sudo hl-smi -L && \
  echo "" && \
  sudo hl-smi -q | grep Firmware
  echo "" && \
  sudo hl-smi

  start_docker

}


apt-mark-hold-habana-packages() {

  echo ""
  echo -e "apt-mark-hold-habana-packages" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  sudo apt-mark hold habanatools habanalabs-container-runtime habanalabs-rdma-core habanalabs-dkms habanalabs-thunk habanalabs-firmware-tools habanalabs-graph habanatools habanalabs-qual

  sudo apt-mark hold habanalabs-sw-tools 2>&1 | tee /dev/null

  sudo apt-mark hold habanalabs-firmware 2>&1 | tee /dev/null
  sudo apt-mark hold habanalabs-firmware-odm 2>&1 | tee /dev/null

}


apt-mark-unhold-habana-packages() {

  echo ""
  echo -e "apt-mark-unhold-habana-packages" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  sudo apt-mark unhold habanatools habanalabs-container-runtime habanalabs-rdma-core habanalabs-dkms habanalabs-thunk habanalabs-firmware-tools habanalabs-graph habanatools habanalabs-qual

  sudo apt-mark unhold habanalabs-sw-tools 2>&1 | tee /dev/null

  sudo apt-mark unhold habanalabs-firmware 2>&1 | tee /dev/null
  sudo apt-mark unhold habanalabs-firmware-odm 2>&1 | tee /dev/null

}


check-gaudi-port() {

  echo ""
  echo -e "check-gaudi-port" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  echo "Port Type"
  echo ""
  hl-smi -Q bus_id -f csv,noheader | head -n 1 | xargs -I {} hl-smi -n ports -i {}
  # port 8: external
  # port 22: external
  # port 23: external
  echo ""

  #hl-smi -Q bus_id -f csv,noheader | xargs -t -I {} hl-smi -n link -P $(echo {0..23}|tr ' ' ',') -i {} 2>&1
  #echo ""

  Habana_AI_Cards=$(lspci | grep Habana | wc -l)
  echo "Habana_AI_Cards: ${Habana_AI_Cards}"
  echo ""

  # for ((i = 1; i <= ${Habana_AI_Cards}; i++))
  # do
  #   echo $i
  # done

  # hl-smi -Q bus_id -f csv,noheader | xargs -t -I bus_id hl-smi -n link -P $(echo {0..23}|tr ' ' ',') -i bus_id 2>&1

  while IFS= read -r bus_id; do
    echo "${bus_id}"
    hl-smi -n link -P $(echo {0..23}|tr ' ' ',') -i ${bus_id} 2>&1
    echo ""
    hl-smi -n link -P $(echo {0..23}|tr ' ' ',') -i ${bus_id} | grep DOWN
    echo ""
    echo ""
  done <<< "$(hl-smi -Q bus_id -f csv,noheader)"

}


manage_network_ifs-flip() {

  echo ""
  echo -e "manage_network_ifs-flip" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  sudo /opt/habanalabs/qual/gaudi2/bin/manage_network_ifs.sh --down
  echo ""
  sleep 4
  sudo /opt/habanalabs/qual/gaudi2/bin/manage_network_ifs.sh --up
  sleep 4
  echo ""

  sudo /opt/habanalabs/qual/gaudi2/bin/manage_network_ifs.sh --down
  echo ""
  sleep 4
  sudo /opt/habanalabs/qual/gaudi2/bin/manage_network_ifs.sh --up
  sleep 4
  echo ""

  echo ""

}



# -- end Habana Labs


# system ops

onecloud-system-reboot() {

  if [ $# -eq 1 ]; then

    Server_Name="$1"

    echo ""
    echo -e "System Reboot take about 5 minutes" | boxes -d stone -a hcvcjc -p a2v0 -s 80
    echo ""

    ssh-keyscan ${Server_Name} >> $HOME/.ssh/known_hosts

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo dmesg"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "wall System Reboot in 1 minutes" 2>&1 | tee /dev/null
    echo ""

    sleep 60

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo reboot" 2>&1 | tee /dev/null
    echo ""

    MAX_SSH_WAIT_TIME=900
    SSH_WAIT_TIME=270

    echo "Waiting for OS Boot Process..."
    sleep ${SSH_WAIT_TIME}

    local SSH_STATUS=$(nmap ${Server_Name} -Pn -p ssh | egrep -io 'open|closed|filtered')
    echo "${Server_Name} SSH_WAIT_TIME=${SSH_WAIT_TIME} SSH_STATUS=${SSH_STATUS}"
    echo ""

    while [[ "${SSH_STATUS}" != "open" ]]
    do

        sleep 3
        SSH_WAIT_TIME=$((${SSH_WAIT_TIME}+3))

        if [[ $SSH_WAIT_TIME -gt $MAX_SSH_WAIT_TIME ]]; then
            echo "${Server_Name} does not boot in 10 minutes. Contact Support."
            echo ""
            exit 1
            #break
        fi

        SSH_STATUS=$(nmap ${Server_Name} -Pn -p ssh | egrep -io 'open|closed|filtered')
        echo "${Server_Name} SSH_WAIT_TIME=${SSH_WAIT_TIME} SSH_STATUS=${SSH_STATUS}"
        echo ""

    done

    if [[ "${SSH_STATUS}" == "open" ]]; then

      ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a; echo ''; sudo hl-smi"

#       ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no -T ae-jenkins@${Server_Name} <<'EOL'
#           source ~/workspace/OneCloud/System/env && \
#           sudo umount /devops 2>&1 | tee /dev/null && \
#           sudo mount -t nfs -o vers=3,timeo=10 HF2COREBAEDEVCLOUD-DM.cps.intel.com:/fs_HF2AEDEVCLOUD_HOME  /devops  2>&1 | tee /dev/null  && \
#           sudo umount /nfs_home_${NEW_USER} 2>&1 | tee /dev/null  && \
#           sudo mount --bind /devops/${NEW_USER} /nfs_home_${NEW_USER}
# EOL

    fi

  else
    echo "Usage: onecloud-system-reboot ${Server_Name}"
  fi

}


onecloud-system-load_vfio_pci_driver() {

  echo ""
  echo -e "onecloud-system-load_vfio_pci_driver" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    Server_Name=$1

    ssh-keyscan ${Server_Name} >> $HOME/.ssh/known_hosts

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo dmesg"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "hostname; echo ''; source ${WORKSPACE}/onecloud-infra.sh && load_vfio_pci_driver; echo ''; print_all_version"
    echo ""

  else
    echo "Usage: onecloud-system-load_vfio_pci_driver Server_Name"
  fi

}


onecloud-system-load_habana_driver() {

  echo ""
  echo -e "onecloud-system-load_habana_driver" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    Server_Name=$1

    ssh-keyscan ${Server_Name} >> $HOME/.ssh/known_hosts

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo dmesg"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "hostname; echo ''; source ${WORKSPACE}/onecloud-infra.sh && load_habana_driver && echo ''; print_all_version"
    echo ""

  else
    echo "Usage: onecloud-system-load_habana_driver Server_Name"
  fi

}


onecloud-system-restart_docker() {

  echo ""
  echo -e "onecloud-system-restart_docker" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    Server_Name=$1

    ssh-keyscan ${Server_Name} >> $HOME/.ssh/known_hosts

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo dmesg"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "hostname; echo ''; source ${WORKSPACE}/onecloud-infra.sh && stop_docker && start_docker"
    echo ""

  else
    echo "Usage: onecloud-system-load_habana_driver Server_Name"
  fi

}


onecloud-system-power-status() {

  echo ""
  echo -e "onecloud-system-power-status" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    BMC_HOST="bmc-$1"
    echo "BMC_HOST=${BMC_HOST}"
    echo ""

    ipmitool -H ${BMC_HOST} -U ${BMC_USERNAME} -P ${BMC_PASSWORD} -I lanplus power status
  else
    echo "Usage: onecloud-system-power-status Server_Name"
  fi

}


onecloud-system-power-on() {

  echo ""
  echo -e "onecloud-system-power-on" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    BMC_HOST="bmc-$1"
    echo "BMC_HOST=${BMC_HOST}"
    echo ""

    echo "Check Power Status."
    POWER_STATUS=$(ipmitool -H ${BMC_HOST} -U ${BMC_USERNAME} -P ${BMC_PASSWORD} -I lanplus power status)
    echo "POWER_STATUS=${POWER_STATUS}"
    echo ""

    date
    echo ""

    ipmitool -H ${BMC_HOST} -U ${BMC_USERNAME} -P ${BMC_PASSWORD} -I lanplus power on
    sleep 10
    date
    echo ""

    echo "Check Power Status."
    POWER_STATUS=$(ipmitool -H ${BMC_HOST} -U ${BMC_USERNAME} -P ${BMC_PASSWORD} -I lanplus power status)
    echo "POWER_STATUS=${POWER_STATUS}"
    echo ""

  else
    echo "Usage: onecloud-system-power-on Server_Name"
  fi

}


onecloud-system-power-cycle-bmc() {

  echo ""
  echo -e "onecloud-system-power-cycle-bmc" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    SERVER="$1"
    BMC_HOST="bmc-$1"

    echo "SERVER=${SERVER}"
    echo "BMC_HOST=${BMC_HOST}"
    echo ""

    date
    echo ""

    # ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${SERVER} "sudo shutdown -h now" 2>&1 | tee /dev/null
    # echo ""

    # echo "Waiting 180 seconds for OS shutdown."
    # sleep 180
    # echo ""

    echo "Check Power Status."
    POWER_STATUS=$(ipmitool -H ${BMC_HOST} -U ${BMC_USERNAME} -P ${BMC_PASSWORD} -I lanplus power status)
    echo "POWER_STATUS=${POWER_STATUS}"
    echo ""

    echo "Make Sure Power is off"
    echo "Power off"
    ipmitool -H ${BMC_HOST} -U ${BMC_USERNAME} -P ${BMC_PASSWORD} -I lanplus power off
    sleep 10
    echo ""

    POWER_STATUS=$(ipmitool -H ${BMC_HOST} -U ${BMC_USERNAME} -P ${BMC_PASSWORD} -I lanplus power status)
    echo "POWER_STATUS=${POWER_STATUS}"
    echo ""

    echo "Power On"
    ipmitool -H ${BMC_HOST} -U ${BMC_USERNAME} -P ${BMC_PASSWORD} -I lanplus power on
    sleep 10
    echo ""

    POWER_STATUS=$(ipmitool -H ${BMC_HOST} -U ${BMC_USERNAME} -P ${BMC_PASSWORD} -I lanplus power status)
    echo "POWER_STATUS=${POWER_STATUS}"
    echo ""

    MAX_SSH_WAIT_TIME=600
    SSH_WAIT_TIME=0

    local SSH_STATUS=$(nmap ${SERVER} -Pn -p ssh | egrep -io 'open|closed|filtered')

    while [[ "${SSH_STATUS}" != "open" ]]
    do

        sleep 5
        SSH_WAIT_TIME=$((${SSH_WAIT_TIME}+3))

        if [[ $SSH_WAIT_TIME -gt $MAX_SSH_WAIT_TIME ]]; then
            echo "Server does not boot in ${MAX_SSH_WAIT_TIME} seconds. Contact Support."
            echo ""
            exit 1
            #break
        fi

        SSH_STATUS=$(nmap ${SERVER} -Pn -p ssh | egrep -io 'open|closed|filtered')
        echo "SSH_WAIT_TIME=${SSH_WAIT_TIME} SSH_STATUS=${SSH_STATUS}"
        echo ""

    done

    if [[ "${SSH_STATUS}" == "open" ]]; then
        echo "Server is Ready."

        ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no -T ae-jenkins@${SERVER} <<'EOL'
          source ~/workspace/OneCloud/System/env && \
          sudo umount /devops 2>&1 | tee /dev/null && \
          sudo mount -t nfs -o vers=3,timeo=10 HF2COREBAEDEVCLOUD-DM.cps.intel.com:/fs_HF2AEDEVCLOUD_HOME  /devops  2>&1 | tee /dev/null  && \
          sudo umount /nfs_home_${NEW_USER} 2>&1 | tee /dev/null  && \
          sudo mount --bind /devops/${NEW_USER} /nfs_home_${NEW_USER}
EOL

    fi

  else
    echo "Usage: onecloud-system-power-cycle-bmc Server_Name"
  fi

} #


onecloud-modprobe-habanalabs() {

  echo ""
  echo -e "onecloud-modprobe-habanalabs" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    Server_Name=$1

    ssh-keyscan ${Server_Name} >> $HOME/.ssh/known_hosts

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo dmesg"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "hostname; echo ''; source ${WORKSPACE}/onecloud-infra.sh && modprobe-habanalabs && echo ''; print_all_version"
    echo ""

  else
    echo "Usage: onecloud-modprobe-habanalabs Server_Name"
  fi

}


onecloud-install-habana-packages() {

  echo ""
  echo -e "onecloud-install-habana-packages" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    Server_Name=$1

    ssh-keyscan ${Server_Name} >> $HOME/.ssh/known_hosts

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo dmesg"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "hostname; echo ''; source ${WORKSPACE}/onecloud-infra.sh && install-habana-packages-latest-release && echo ''; print_all_version"
    echo ""

  else
    echo "Usage: onecloud-install-habana-packages Server_Name"
  fi

}


onecloud-set-cpu-performance() {

  echo ""
  echo -e "onecloud-set-cpu-performance" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    Server_Name=$1

    ssh-keyscan ${Server_Name} >> $HOME/.ssh/known_hosts

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo dmesg"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "hostname; echo ''; source ${WORKSPACE}/onecloud-infra.sh && set-cpu-performance && echo ''; print-cpu-performance"
    echo ""

  else
    echo "Usage: onecloud-set-cpu-performance Server_Name"
  fi

}

onecloud-mount() {

  echo ""
  echo -e "onecloud-mount" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    Server_Name=$1

    ssh-keyscan ${Server_Name} >> $HOME/.ssh/known_hosts

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo dmesg"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "hostname; echo ''; source ${WORKSPACE}/onecloud-infra.sh && df -h; echo ''; sudo mount -a; echo ''; df -h; echo '' "
    echo ""

  else
    echo "Usage: onecloud-mount Server_Name"
  fi

}


onecloud-install-docker-latest() {

  echo ""
  echo -e "onecloud-install-docker-latest" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    Server_Name=$1

    ssh-keyscan ${Server_Name} >> $HOME/.ssh/known_hosts

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo dmesg"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "hostname; echo ''; source ${WORKSPACE}/onecloud-infra.sh && df -h; echo ''; purge-docker; echo ''; install-docker-latest; echo '' "
    echo ""

  else
    echo "Usage: onecloud-install-docker-latest Server_Name"
  fi

}


onecloud-add-user-docker-group() {

  echo ""
  echo -e "onecloud-add-user-docker-group" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    Server_Name=$1

    ssh-keyscan ${Server_Name} >> $HOME/.ssh/known_hosts

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo dmesg"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "hostname; echo ''; source ${WORKSPACE}/env && source ${WORKSPACE}/onecloud-infra.sh && df -h; echo ''; add-user-docker-group; echo '' "
    echo ""

  else
    echo "Usage: onecloud-add-user-docker-group Server_Name"
  fi

}


onecloud-reclaim-storage() {

  echo ""
  echo -e "onecloud-reclaim-storage" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    Server_Name=$1

    ssh-keyscan ${Server_Name} >> $HOME/.ssh/known_hosts

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo dmesg"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "hostname; echo ''; source ${WORKSPACE}/env && source ${WORKSPACE}/onecloud-infra.sh && df -h; echo ''; reclaim-storage; echo ''; df -h"
    echo ""

  else
    echo "Usage: onecloud-add-user-docker-group Server_Name"
  fi

}


onecloud-card-reset-hl-fw-loader () {

  echo ""
  echo -e "onecloud-card-reset-hl-fw-loader" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    Server_Name=$1

    ssh-keyscan ${Server_Name} >> $HOME/.ssh/known_hosts

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo dmesg"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "hostname; echo ''; source ${WORKSPACE}/env && source ${WORKSPACE}/onecloud-infra.sh && df -h; echo ''; card-reset-hl-fw-loader"
    echo ""

  else
    echo "Usage: onecloud-card-reset-hl-fw-loader Server_Name"
  fi

}


onecloud-check-gaudi-port() {

  echo ""
  echo -e "onecloud-check-gaudi-port" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    Server_Name=$1

    ssh-keyscan ${Server_Name} >> $HOME/.ssh/known_hosts

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo dmesg"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "hostname; echo ''; source ${WORKSPACE}/env && source ${WORKSPACE}/onecloud-infra.sh && df -h; echo ''; check-gaudi-port"
    echo ""

  else
    echo "Usage: onecloud-check-gaudi-port Server_Name"
  fi

}


onecloud-manage_network_ifs-flip() {

  echo ""
  echo -e "onecloud-manage_network_ifs-flip" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  if [ $# -eq 1 ]; then

    Server_Name=$1

    ssh-keyscan ${Server_Name} >> $HOME/.ssh/known_hosts

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "sudo dmesg"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "who -a"
    echo ""

    ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "hostname; echo ''; source ${WORKSPACE}/env && source ${WORKSPACE}/onecloud-infra.sh && manage_network_ifs-flip"
    echo ""

  else
    echo "Usage: onecloud-manage_network_ifs-flip Server_Name"
  fi

}


onecloud-system-ops() {

  echo ""
  echo -e "onecloud-system-ops" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  echo "USER=${USER}"
  echo ""

  if [ $# -eq 2 ]; then

    Server_Name=$1
    Server_Name="$1.jf.intel.com"
    OneCloud_System_Ops=$2

    echo "Server_Name=${Server_Name}"
    echo "OneCloud_System_Ops=${OneCloud_System_Ops}"
    echo ""
    #echo "${BMC_PASSWORD}" >> ${WORKSPACE}/BMC_PASSWORD

    if [[ "${OneCloud_System_Ops}" != "Power_Cycle_BMC" ]]; then

      #ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "mkdir -p ~/workspace/OneCloud/System"

      ssh -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ae-jenkins@${Server_Name}  "mkdir -p ${WORKSPACE}"

      scp -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ${WORKSPACE}/env  ae-jenkins@${Server_Name}:${WORKSPACE}/

      scp -i ~/.ssh/id_rsa-reserve-hf-2 -o StrictHostKeyChecking=no  ${WORKSPACE}/${AE_AUTOMATION_REPO_NAME}/scripts/onecloud-infra.sh  ae-jenkins@${Server_Name}:${WORKSPACE}/

    fi

    echo "+------------------------------------------------------------------------------+"
    echo ""

    if [ "${OneCloud_System_Ops}" == "Reboot" ]; then
      onecloud-system-reboot ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "Restart_Docker" ]; then
      onecloud-system-restart_docker ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "vfio-pci_Driver" ]; then
      onecloud-system-load_vfio_pci_driver ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "habanalabs_Driver" ]; then
      onecloud-system-load_habana_driver ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "Check_Power_Status" ]; then
      onecloud-system-power-status ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "Power_On" ]; then
      onecloud-system-power-on ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "Power_Cycle_BMC" ]; then
      onecloud-system-power-cycle-bmc ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "modprobe-habanalabs" ]; then
      onecloud-modprobe-habanalabs ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "install-habana-packages" ]; then
      onecloud-install-habana-packages ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "set-cpu-performance" ]; then
      onecloud-set-cpu-performance ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "mount" ]; then
      onecloud-mount ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "install-docker-latest" ]; then
      onecloud-install-docker-latest ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "add-user-docker-group" ]; then
      onecloud-add-user-docker-group ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "reclaim-storage" ]; then
      onecloud-reclaim-storage ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "card-reset-hl-fw-loader" ]; then
      onecloud-card-reset-hl-fw-loader ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "check-gaudi-port" ]; then
      onecloud-check-gaudi-port ${Server_Name}
    fi

    if [ "${OneCloud_System_Ops}" == "manage_network_ifs-flip" ]; then
      onecloud-manage_network_ifs-flip ${Server_Name}
    fi

  else
    echo "Usage: onecloud-system-ops Server_Name OneCloud_System_Ops"
  fi

}


# end system ops


check-habana-packages() {

  echo ""
  echo -e "check-habana-packages" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  sudo apt list --installed | grep habana && rc=0 || rc=1

  if [[ ${rc} == 1 ]]; then
    echo "Need to install habanalabs packages"
    purge-habana-package
    install-habana-packages-latest-release
  fi

}


check-hl-smi() {

  echo ""
  echo -e "check-hl-smi" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  sudo hl-smi && rc=0 || rc=1

  if [[ ${rc} == 1 ]]; then
    echo "Need to re-install habanalabs packages"
    purge-habana-package
    install-habana-packages-latest-release
  fi

}


reboot_check() {

  echo ""
  echo -e "reboot_check - Check whether system reboot is required or not." | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  uptime_check=$(uptime  | cut -d ',' -f1)

  if [[ ${uptime_check} == *"days"* ]]; then

    echo """
System has been up for `uptime -p`.
Need to Reboot.

""" | boxes -d stone -a hcvcjc -p a2v0 -s 80

    sudo shutdown -r +1

  else

    pid_large=$(ps -o pid --sort -pid | head -2 | tail -1)
    echo $?
    echo "pid_large=${pid_large}"
    pid_large=${pid_large// /}
    echo $?
    echo "pid_large=${pid_large}"
    echo ""

    if [[ "$(bc -l <<<"(${pid_large}>${pid_reboot_threshold})")" == "1" ]]; then
      echo """System Need to Reboot.""" | boxes -d stone -a hcvcjc -p a2v0 -s 80
      sudo shutdown -r +1
    fi

  fi

} # reboot_check


check_card_process() {

  IN_USE="False"

  cards=$(lspci | grep acc  | wc -l)
  echo "cards=${cards}"
  echo ""


  for (( c=1; c<=$cards; c++ ))
  do
    #echo "Welcome $c times"
    card_usage=$(sudo hl-smi | tail -n $(($cards+2-$c)) | head -n 1)
    echo "card_usage=${card_usage}"
    echo ""

    PID=$(echo ${card_usage} | awk '{print $3}')
    echo "PID=${PID}"
    echo ""

    Process_name=$(echo ${card_usage} | awk '{print $3}')
    echo "Process_name=${Process_name}"
    echo ""

    if [ "${Process_name}" != "N/A" ]; then
      IN_USE="True"
    fi

    echo ""
    echo "-------"
    echo ""
  done

  echo "IN_USE=${IN_USE}"

  echo ${IN_USE} > ./IN_USE

  if [ "${IN_USE}" == "False" ]; then
    echo "Terminate this job"
  fi

}


reservation_record() {

  #RESERVATION_RECORD="${JOB_BASE_NAME}, ${BUILD_NUMBER}, WW_`date +%U`, `date`, `date +%s`, `hostname`, `whoami`"

  RESERVATION_RECORD="${JOB_BASE_NAME}, ${BUILD_NUMBER}, ${Reservation_Type}, WW_`date +%U`, ${reservationStartTime}, ${reservationStartDateTimeString}, ${NODE_NAME}, ${USER}"
  echo "RESERVATION_RECORD"
  echo "${RESERVATION_RECORD}"
  echo ""

  mkdir -p /devops/ae-jenkins/RESERVATION_RECORD

  echo "${RESERVATION_RECORD}" >> "/devops/ae-jenkins/RESERVATION_RECORD/`date +%Y%m`"
  echo "${RESERVATION_RECORD}" >> "/devops/ae-jenkins/RESERVATION_RECORD/`date +%Y%m%d`"
  echo "${RESERVATION_RECORD}" >> "/devops/ae-jenkins/RESERVATION_RECORD/WW_`date +%U`"
  echo "${RESERVATION_RECORD}" >> "/devops/ae-jenkins/RESERVATION_RECORD/${USER}_`date +%U`"

}


reservation_record_end() {

  echo "reservation_record_end"
  echo "reservationEndTime=${reservationEndTime}"
  echo "duration=${duration}"
  echo ""

  sed -i.bak "s/${BUILD_NUMBER}.*$/&, ${reservationEndTime}, ${duration}/" "/devops/ae-jenkins/RESERVATION_RECORD/`date +%Y%m`"
  sed -i.bak "s/${BUILD_NUMBER}.*$/&, ${reservationEndTime}, ${duration}/" "/devops/ae-jenkins/RESERVATION_RECORD/`date +%Y%m%d`"
  sed -i.bak "s/${BUILD_NUMBER}.*$/&, ${reservationEndTime}, ${duration}/" "/devops/ae-jenkins/RESERVATION_RECORD/WW_`date +%U`"
  sed -i.bak "s/${BUILD_NUMBER}.*$/&, ${reservationEndTime}, ${duration}/" "/devops/ae-jenkins/RESERVATION_RECORD/${USER}_`date +%U`"

}


# helper

set-cpu-performance() {

  echo ""
  echo -e "set-cpu-performance" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>&1 | tee /dev/null
  echo ""
  echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils 2>&1 | tee /dev/null
  echo ""

  echo 0 | sudo tee /sys/devices/system/cpu/cpu*/power/energy_perf_bias 2>&1 | tee /dev/null
  echo ""

}


purge-docker() {

  echo ""
  echo -e "purge-docker" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  sudo docker stop $(docker ps -aq)

  sudo apt-get purge -y --allow-change-held-packages --allow-downgrades \
          docker-ce docker-ce-cli containerd.io \
          docker-buildx-plugin docker-compose-plugin \
          docker-ce-rootless-extras

  # sudo apt install docker.io -y

  # sudo systemctl start docker
  # sudo systemctl enable docker
  # sudo systemctl daemon-reload
  # sudo systemctl restart docker
  # sudo systemctl status docker

}


install-docker-latest() {

  echo ""
  echo -e "Install docker latest" | boxes -d stone -a hcvcjc -p a2v0 -s 80
  echo ""

  sudo mkdir -m 0755 -p /etc/apt/keyrings
  sudo rm -rf /etc/apt/keyrings/docker.gpg > /dev/null
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [trusted=yes arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update

  sudo apt-cache madison docker-ce
  # sudo -E apt-get remove -y docker docker-engine docker.io containerd runc 2>&1 | tee /dev/null

  sudo -E DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y \
    --allow-change-held-packages \
    --allow-downgrades \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    docker-ce-rootless-extras 2>&1 | tee /dev/null
  sudo apt-mark hold docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>&1 | tee /dev/null

  sudo systemctl status docker.service docker.socket containerd.service -l --no-pager 2>&1 | tee /dev/null
  echo ""

  echo "docker.service NRestarts"
  sudo systemctl show docker.service -p NRestarts 2>&1 | tee /dev/null
  sudo systemctl reset-failed docker.service 2>&1 | tee /dev/null
  echo ""

  echo "Docker Installation Done"

  echo ""
  echo "sync"
  sync

  echo ""
  echo "wait 11 seconds"
  sleep 11

  sudo sed -i "s/StartLimitBurst.*/StartLimitBurst=300/g"  /lib/systemd/system/docker.service 2>&1 | tee /dev/null
  sudo cat /lib/systemd/system/docker.service 2>&1 | tee /dev/null
  sudo systemctl daemon-reload
  echo ""

  echo ""
  echo "Run sudo service docker start"
  sudo service docker start 2>&1 | tee /dev/null

  echo ""
  sudo systemctl status docker.service docker.socket containerd.service -l --no-pager 2>&1 | tee /dev/null

  echo ""
  echo "docker.service NRestarts"
  sudo systemctl show docker.service -p NRestarts
  echo ""

  #sudo systemctl enable docker

  echo "add user account to docker group"
  sudo usermod -aG docker `whoami` 2>&1 | tee /dev/null
  sudo usermod -aG docker ${NEW_USER} 2>&1 | tee /dev/null

  sudo usermod -aG docker ae-admin 2>&1 | tee /dev/null
  sudo usermod -aG docker ae-jenkins 2>&1 | tee /dev/null

  echo ""
  sudo docker run hello-world 2>&1 | tee /dev/null

}


start_docker() {

  echo ""
  echo "start_docker"
  echo ""

  sudo systemctl daemon-reload

  echo "start docker.service"
  sudo systemctl start docker.service && echo $? && echo ""

  echo "start docker.service"
  sudo systemctl start docker.socket && echo $? && echo ""

  echo "start containerd.service"
  sudo systemctl start containerd.service && echo $? && echo ""

  sudo service docker restart 2>&1 | tee /dev/null
  sudo systemctl status docker.service docker.socket containerd.service -l --no-pager 2>&1 | tee /dev/null

  echo "sudo journalctl -xeu docker --no-pager"

  systemctl is-active --quiet docker && rc=0 || rc=1
  if [[ ${rc} == 1 ]]; then
    echo "docker service is not running"
  else
    echo "docker service is running"
    docker ps -a 2>&1 | tee /dev/null
    echo ""
    docker images 2>&1 | tee /dev/null
    echo ""
  fi

}


stop_docker() {

  echo ""
  echo "stop_docker"
  echo ""

  docker images 2>&1 | tee /dev/null
  echo ""

  docker ps -a 2>&1 | tee /dev/null
  echo ""

  sudo systemctl stop docker.service 2>&1 | tee /dev/null
  sudo systemctl stop docker.socket 2>&1 | tee /dev/null
  sudo systemctl stop containerd.service 2>&1 | tee /dev/null

  sudo systemctl status docker.service docker.socket containerd.service -l --no-pager 2>&1 | tee /dev/null
  echo ""
  echo ""

  systemctl is-active --quiet docker && rc=0 || rc=1
  if [[ ${rc} == 0 ]]; then
    echo "docker service is running"
  else
    echo "docker service is not running"
  fi

}


add-user-docker-group() {

  echo ""
  echo -e "add-user-docker-group"
  echo ""

  sudo usermod -aG docker `whoami` 2>&1 | tee /dev/null
  sudo usermod -aG docker ${NEW_USER} 2>&1 | tee /dev/null

  sudo apt-get install -y members 2>&1 | tee /dev/null
  echo ""

  echo ""
  echo -e "members of docker group"
  echo ""
  members docker 2>&1 | tee /dev/null
  echo ""

}


remove-container-weeks() {

  echo ""
  echo -e "remove-container-weeks"
  echo ""

  stop_docker
  start_docker

  cat /etc/docker/daemon.json
  echo ""

  docker ps -a
  echo ""

  docker ps -a | wc -l
  echo ""

  seven_days_old_containers=$(docker ps -a | grep Exited | grep "11 days" | wc -l)
  echo "seven_days_old_containers: ${seven_days_old_containers}"

  if [[ ${seven_days_old_containers} -gt 1 ]]; then

    docker ps -a | grep Exited | grep "11 days" | cut -d ' ' -f 1 | xargs sudo docker rm
    echo ""

    docker ps -a
    echo ""

    docker ps -a | wc -l
    echo ""

  fi

  weeks_old_containers=$(docker ps -a | grep Exited | grep weeks | wc -l)
  echo "weeks_old_containers: ${weeks_old_containers}"

  if [[ ${weeks_old_containers} -gt 1 ]]; then

    docker ps -a | grep Exited | grep weeks | cut -d ' ' -f 1 | xargs sudo docker rm
    echo ""

    docker ps -a
    echo ""

    docker ps -a | wc -l
    echo ""

  fi

}


check-root-disk-space() {

  #OneCloud_Report_Channel="https://habanalabs.webhook.office.com/webhookb2/00072444-e850-451d-b045-03eafea537bb@0d4d4539-213c-4ed8-a251-dc9766ba127a>

  echo ""
  echo -e "check-root-disk-space"
  echo ""

  ROOT_DISK_USAGE_WARNING=70

  ROOT_DISK_GUESS=$(blkid  | grep "ext4" | grep "PARTUUID" | tail -n 1 | awk -F':' '{print $1}')
  echo "ROOT_DISK_GUESS: ${ROOT_DISK_GUESS}"

  ROOT_DISK_USAGE=$(df -h | grep "${ROOT_DISK_GUESS}" | awk -F' ' '{print $5}' | cut -d '%' -f1)
  echo "ROOT_DISK_USAGE: ${ROOT_DISK_USAGE}"

  ROOT_DISK_USAGE=$((ROOT_DISK_USAGE + 0))

  if [[ ${ROOT_DISK_USAGE} -gt ${ROOT_DISK_USAGE_WARNING} ]]; then

    JSON="{\"text\": \"`hostname` ${ROOT_DISK_USAGE}\"}"
    echo "JSON"
    echo "${JSON}"
    echo ""

    echo "Sending ..."
    echo \"Content-Type: application/json\" -d \"${JSON}\"
    #\"${OneCloud_Report_Channel}\"
    curl -H "Content-Type: application/json" -d "${JSON}" "${OneCloud_Report_Channel}"
    echo ""


    DISK_REPORT_FILE="${WORKSPACE}/disk_report.txt"
    echo "DISK_REPORT_FILE=${DISK_REPORT_FILE}"

    echo `hostname` >> "${DISK_REPORT_FILE}"
    echo "" >> "${DISK_REPORT_FILE}"

    df -h >> "${DISK_REPORT_FILE}"

    echo "" >> "${DISK_REPORT_FILE}"
    echo "" >> "${DISK_REPORT_FILE}"
    echo "" >> "${DISK_REPORT_FILE}"

    sudo du -hBM --max-depth=1 /home/ | sort -nr >> "${DISK_REPORT_FILE}"

    MESSAGE=$(<${DISK_REPORT_FILE})
    MESSAGE="${MESSAGE//$'\n'/<br />}"
    echo "MESSAGE: ${MESSAGE}"
    echo ""

    #JSON="{\\"text\\": \\"Hello\\"}"
    JSON="{\"text\": \"${MESSAGE}\"}"
    echo "${JSON}"
    echo ""

    echo "Sending ..."
    echo \"Content-Type: application/json\" -d \"${JSON}\"
    curl -H "Content-Type: application/json" -d "${JSON}" "${OneCloud_Report_Channel}"
    echo ""

  fi

}


reclaim-storage() {

  echo ""
  echo -e "reclaim-storage"
  echo ""

  ROOT_DISK_USAGE_WARNING=80
  MINIMUM_ROOT_DISK=200

  ROOT_DISK=$(findmnt -n -o SOURCE /)
  echo "ROOT_DISK: ${ROOT_DISK}"

  ROOT_DISK_SPACE_AVAILABLE=$(df -h | grep "${ROOT_DISK}" | awk -F' ' '{print $4}' | cut -d 'G' -f1)
  ROOT_DISK_SPACE_AVAILABLE=$(echo ${ROOT_DISK_SPACE_AVAILABLE} | bc)
  echo "ROOT_DISK_SPACE_AVAILABLE: ${ROOT_DISK_SPACE_AVAILABLE}"

  ROOT_DISK_USAGE=$(df -h | grep "${ROOT_DISK}" | awk -F' ' '{print $5}' | cut -d '%' -f1)
  ROOT_DISK_USAGE=$((ROOT_DISK_USAGE + 0))
  echo "ROOT_DISK_USAGE: ${ROOT_DISK_USAGE}"

  #CURRENT_EPOCH_TIMESTAMP=$(date +%s)

  #if [[ ${ROOT_DISK_USAGE} -gt ${ROOT_DISK_USAGE_WARNING} ]]; then

  if [[ ${ROOT_DISK_SPACE_AVAILABLE} -lt ${MINIMUM_ROOT_DISK} ||${ROOT_DISK_USAGE} -gt 90 ]]; then

    sudo du -hBM --max-depth=1 /home/ | sort -n
    echo ""

    sudo du -hBM --max-depth=1 /home/ | sort -n | tail -n 7 | head -n 6 | awk -F' ' '{print $2}' > ${WORKSPACE}/reclaim-storage
    cat ${WORKSPACE}/reclaim-storage
    echo ""

    while IFS= read -r home_folder
    do

      echo "${home_folder}" | boxes -d stone -a hcvcjc -p a2v0 -s 80
      sudo du -hBM --max-depth=1 --time ${home_folder} | sort -nr > ${WORKSPACE}/home-sub-folder
      sed -i '1d' ${WORKSPACE}/home-sub-folder
      sed -i '$ d' ${WORKSPACE}/home-sub-folder
      cat ${WORKSPACE}/home-sub-folder
      echo ""

      while IFS= read -r home_sub_folder
      do

        echo "${home_sub_folder}"
        echo "--------"
        echo ""

        home_sub_folder_size=$(echo "${home_sub_folder}" | awk -F' ' '{print $1}' | cut -d 'M' -f1)
        #echo "home_sub_folder_size: ${home_sub_folder_size}"

        home_sub_folder_date=$(echo "${home_sub_folder}" | awk -F' ' '{print $2}')
        #echo "home_sub_folder_date: ${home_sub_folder_date}"

        home_sub_folder_path=$(echo "${home_sub_folder}" | awk -F' ' '{print $4}')
        #echo "home_sub_folder_path: ${home_sub_folder_path}"

        if [[ ${home_sub_folder_size} -gt 10240 && $(date --date="${home_sub_folder_date} UTC" +%s) -lt $(date -d "- 7 days" +%s) ]]; then
          echo "delete ${home_sub_folder_path}"
          echo "${home_sub_folder_path}" >> ${WORKSPACE}/folder-delete
          echo "${home_sub_folder}" >> ${WORKSPACE}/folder-delete-info
          sudo rm -rf ${home_sub_folder_path}
          echo ""
        fi

      done < "${WORKSPACE}/home-sub-folder"
      echo ""

    done < "${WORKSPACE}/reclaim-storage"

    cat ${WORKSPACE}/folder-delete
    echo ""

    cat ${WORKSPACE}/folder-delete-info
    echo ""


    # sudo ls -haltr $(sudo du -hBM --max-depth=1 /home/ | sort -nr | head -n +7 | tail -n 1 | awk -F' ' '{print $2}')
    # echo ""

    # sudo du -h --max-depth=1 --time $(sudo du -hBM --max-depth=1 /home/ | sort -nr | head -n +2 | tail -n 1 | awk -F' ' '{print $2}')
    # echo ""

    # sudo du -hBM --max-depth=1 $(sudo du -hBM --max-depth=1 /home/ | sort -nr | head -n +2 | tail -n 1 | awk -F' ' '{print $2}') | sort -nr
    # echo ""

    # sudo du -sh $(sudo du -hBM --max-depth=1 $(sudo du -hBM --max-depth=1 /home/ | sort -nr | head -n +2 | tail -n 1 | awk -F' ' '{print $2}') | sort -nr | head -n 2 | tail -n 1 | awk -F' ' '{print $2}')
    # echo ""

    # sudo du -h --max-depth=1 $(sudo du -hBM --max-depth=1 $(sudo du -hBM --max-depth=1 /home/ | sort -nr | head -n +2 | tail -n 1 | awk -F' ' '{print $2}') | sort -nr | head -n 2 | tail -n 1 | awk -F' ' '{print $2}')
    # echo ""

    # sudo rm -rf $(sudo du -hBM --max-depth=1 $(sudo du -hBM --max-depth=1 /home/ | sort -nr | head -n +2 | tail -n 1 | awk -F' ' '{print $2}') | sort -nr | head -n 2 | tail -n 1 | awk -F' ' '{print $2}')
    # echo ""

  fi

}










