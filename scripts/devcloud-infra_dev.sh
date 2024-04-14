#!/bin/bash -e
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

export TERM=xterm-256color

sudo apt update
sudo apt install -y boxes

echo -e "OneCloud DevOps" | boxes -d stone -a hcvcjc -p a2v0 -s 80

if [[ -z "${NEW_USER}" || "${NEW_USER}" == "" ]]; then
  export BUILD_NUMBER=1
  export NEW_USER=asanoo
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


# save_env

save_env() {

  echo "saving env to ${WORKSPACE}/env"
  echo ""

  if [ -f ${WORKSPACE}/env ]; then
    rm ${WORKSPACE}/env 2>&1 | tee /dev/null
  fi

  echo "export WORKSPACE=${WORKSPACE}" >> ${WORKSPACE}/env
  echo "export BUILD_NUMBER=${BUILD_NUMBER}" >> ${WORKSPACE}/env
  echo "" >> ${WORKSPACE}/env

  echo "export DOMAIN=${DOMAIN}" >> ${WORKSPACE}/env
  echo "export NEW_USER=${NEW_USER}" >> ${WORKSPACE}/env
  echo "export Additional_User=${Additional_User}" >> ${WORKSPACE}/env
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
      #echo "new_user_name=${new_user_name}"
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

  ssh-keyscan reserve-hf-2.amr.corp.intel.com >> $HOME/.ssh/known_hosts

  RESERVE_SERVER=$(hostname -A | cut -d ' ' -f1)
  echo "RESERVE_SERVER=${RESERVE_SERVER}"
  echo ""

  echo "export RESERVE_SERVER=${RESERVE_SERVER}" >> ${WORKSPACE}/env

  ssh -i ~/.ssh/id_rsa-reserve-hf-2  ae-jenkins@reserve-hf-2.amr.corp.intel.com  "mkdir -p ~/workspace/USER_INFO"
  scp -i ~/.ssh/id_rsa-reserve-hf-2  ${WORKSPACE}/env  ae-jenkins@reserve-hf-2.amr.corp.intel.com:~/workspace/USER_INFO/env.${BUILD_NUMBER}
  scp -i ~/.ssh/id_rsa-reserve-hf-2  ${WORKSPACE}/devcloud-infra.sh  ae-jenkins@reserve-hf-2.amr.corp.intel.com:~/workspace/USER_INFO/devcloud-infra.${BUILD_NUMBER}.sh

  ssh -i ~/.ssh/id_rsa-reserve-hf-2  ae-jenkins@reserve-hf-2.amr.corp.intel.com  "source ~/workspace/USER_INFO/env.${BUILD_NUMBER} && source ~/workspace/USER_INFO/devcloud-infra.${BUILD_NUMBER}.sh && save_user_account_info"
  echo ""

  scp -i ~/.ssh/id_rsa-reserve-hf-2  ae-jenkins@reserve-hf-2.amr.corp.intel.com:~/workspace/USER_INFO/USER_INFO_${BUILD_NUMBER}.txt  ${WORKSPACE}/
  echo ""

  # scp .profile and .bashrc if necessary

  cat ./USER_INFO_${BUILD_NUMBER}.txt
  echo ""

  scp -i ~/.ssh/id_rsa-reserve-hf-2  ae-jenkins@reserve-hf-2.amr.corp.intel.com:~/workspace/USER_INFO/USER_INFO_${BUILD_NUMBER}.authorized_keys  ${WORKSPACE}/
  echo ""

  cat ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.authorized_keys
  echo ""

}


save_user_account_info() {

  mkdir -p ${WORKSPACE}
  rm -f ~/workspace/USER_INFO/USER_INFO_${BUILD_NUMBER}.txt
  touch ~/workspace/USER_INFO/USER_INFO_${BUILD_NUMBER}.txt

  new_user_name=$(sudo ls -la /home/${NEW_USER}/.ssh/authorized_keys | awk -F' '  '{print $3}')
  new_user_group_name=$(sudo ls -la /home/${NEW_USER}/.ssh/authorized_keys | awk -F' '  '{print $4}')
  echo "" | tee -a ~/workspace/USER_INFO/USER_INFO_${BUILD_NUMBER}.txt
  echo "new_user_name=${new_user_name}" | tee -a ~/workspace/USER_INFO/USER_INFO_${BUILD_NUMBER}.txt
  echo "new_user_group_name=${new_user_group_name}" | tee -a ~/workspace/USER_INFO/USER_INFO_${BUILD_NUMBER}.txt

  new_user_id=$(id -u $new_user_name)
  new_user_group_id=$(id -g $new_user_name)
  echo "" | tee -a ~/workspace/USER_INFO/USER_INFO_${BUILD_NUMBER}.txt
  echo "new_user_id=${new_user_id}" | tee -a ~/workspace/USER_INFO/USER_INFO_${BUILD_NUMBER}.txt
  echo "new_user_group_id=${new_user_group_id}" | tee -a ~/workspace/USER_INFO/USER_INFO_${BUILD_NUMBER}.txt
  echo ""

  echo "~/workspace/USER_INFO/USER_INFO_${BUILD_NUMBER}.txt"
  echo ""

  cat ~/workspace/USER_INFO/USER_INFO_${BUILD_NUMBER}.txt
  echo ""

  sudo cp /home/${NEW_USER}/.ssh/authorized_keys  ~/workspace/USER_INFO/USER_INFO_${BUILD_NUMBER}.authorized_keys
  sudo chown `id -u`.`id -g` ~/workspace/USER_INFO/USER_INFO_${BUILD_NUMBER}.authorized_keys

}


#sudo groupadd -g ${NEW_GID} "Software-SG" 2>&1 | tee /dev/null

#sudo useradd -u ${NEW_UID} -g ${NEW_GID} -d "/storage/${NEW_USER_NAME}" -G sudo -s /bin/bash $NEW_USER_NAME -p "$(openssl passwd -1 Hab@12345)"


create_user_account() {

  if [ -f ./USER_INFO_${BUILD_NUMBER}.txt ]; then

    source ./USER_INFO_${BUILD_NUMBER}.txt

    # group

    getent group ${new_user_group_id} && NEW_USER_GRP_EXISTS_RC=0 || NEW_USER_GRP_EXISTS_RC=1
    echo "NEW_USER_GRP_EXISTS_RC=${NEW_USER_GRP_EXISTS_RC}"
    echo ""

    if [[ ${NEW_USER_GRP_EXISTS_RC} == 1 ]]; then
      sudo groupadd -g ${new_user_group_id} ${new_user_group_name}
    else
      sudo groupmod -g ${new_user_group_id} ${new_user_group_name}
    fi

    # user

    new_user_home="/home/${new_user_name}"

    # check useraccount first
    id ${new_user_name} && NEW_USER_ACC_EXISTS_RC=0 || NEW_USER_ACC_EXISTS_RC=1
    echo "NEW_USER_ACC_EXISTS_RC=${NEW_USER_ACC_EXISTS_RC}"
    echo ""

    if [[ ${NEW_USER_ACC_EXISTS_RC} == 1 ]]; then

      echo "Create User Account ${NEW_USER} -u ${new_user_id} -g ${new_user_group_id} -m -d ${new_user_home} -G ${new_user_group_name}"
      sudo useradd -u ${new_user_id} -g ${new_user_group_id} -m -d ${new_user_home} -G ${new_user_group_name} -s /bin/bash ${new_user_name} -p "$(openssl passwd -1 ${new_user_id}_${new_user_group_id})"
      sudo chown ${new_user_id}.${new_user_group_id} ${new_user_home}

      # sudo rsync -arPhv ~/.profile  ${new_user_home}/
      # sudo rsync -arPhv ~/.bashrc   ${new_user_home}/

      # sudo chown -R ${new_user_id}.${new_user_group_id} ${new_user_home}/.profile
      # sudo chown -R ${new_user_id}.${new_user_group_id} ${new_user_home}/.bashrc

      # sudo chmod 644 ${new_user_home}/.profile 2>&1 | tee /dev/null
      # sudo chmod 644 ${new_user_home}/.bashrc 2>&1 | tee /dev/null

    else
      sudo usermod -u ${new_user_id} ${new_user_name}
    fi
    echo "Create User Account ${NEW_USER} created."

    sudo echo "${NEW_USER}    ALL=NOPASSWD:ALL,!SU,!PASSWD,!VISUDO,!SUDOERS,!CH,!APT,!CAT,!EDITOR,!REBOOT,!TOOLS,!SERVICE_SYSTEMCTL,!RM,!USERMOD,!GROUPMOD" | sudo tee -a /etc/sudoers

    sudo usermod -aG docker ${NEW_USER}

    sudo mkdir -p ${new_user_home}/.ssh
    sudo ls -la ${new_user_home}

    echo "Update user ${NEW_USER} authorized_keys"
    sudo cp ${WORKSPACE}/USER_INFO_${BUILD_NUMBER}.authorized_keys ${new_user_home}/.ssh/authorized_keys

    sudo chown -R ${new_user_id}.${new_user_group_id} ${new_user_home}
    sudo chmod 744 ${new_user_home}/.ssh

    sudo chmod 600 ${new_user_home}/.ssh/* 2>&1 | tee /dev/null

    ls -la ${new_user_home}
    echo ""

    echo "Check ${new_user_name} group"
    getent group | grep ${new_user_name}
    echo ""

  else
    echo "./USER_INFO_${BUILD_NUMBER}.txt NOT FOUND."
  fi

}


additional_user() {

  echo "additional_user"
  echo ""

  if [[ ! -z "${Additional_User}" && "${Additional_User}" != "" ]]; then

    Additional_User=`echo ${Additional_User}`

    IFS=',' read -r -a additional_user <<<"$Additional_User"

    for i in "${additional_user[@]}"
    do
      echo "$i"
    done

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

  distributor=$(lsb_release -is)
  echo "distributor=${distributor}"

  if [ "${distributor}" == "Ubuntu" ]; then
    sudo apt list --installed | grep habana
  fi

}


print_all_version() {

  show_installed_habana
  echo ""
  show_h_pci_devices
  echo ""
  sudo hl-smi
  echo ""

  sudo hl-smi -q | head -n 88
  echo ""

  docker version
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


# -- end Habana Labs







