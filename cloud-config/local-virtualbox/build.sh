#!/usr/bin/env bash

pubKeyPath=$1
pubKeyEscaped=$(cat ${pubKeyPath} | sed -e 's/\//\\\//g')
hostIp=${2:-$(hostname -I | awk '{print $1;}')}

echo "Using ${hostIp} as this host's IP address"

remoteImg="https://cloud-images.ubuntu.com/releases/cosmic/release/ubuntu-18.10-server-cloudimg-amd64.img"
remoteTomcatTarball="http://www.apache.org/dist/tomcat/tomcat-8/v8.5.37/bin/apache-tomcat-8.5.37.tar.gz"
localImg="ubuntu-18.10-server-cloudimg-amd64.img"
localRaw="ubuntu-18.10-server-cloudimg-amd64.raw"
localVdi="ubuntu-18.10-server-cloudimg-amd64.vdi"
localAggregateWar="aggregate.war"
localTomcatTarball="apache-tomcat-8.5.37.tar.gz"
cloudConfigIso="my-seed.iso"
vmName="aggregate-cloud"

# Reset the VM
vboxmanage controlvm ${vmName} poweroff
vboxmanage unregistervm ${vmName} --delete

# Prepare assets for the VM
if [[ ! -f ${localAggregateWar} ]]; then
  ../../gradlew -p ../..  clean build -xtest -PwarMode=complete
  cp ../../build/libs/*.war aggregate.war
fi

if [[ ! -f ${localTomcatTarball} ]]; then
  wget -O ${localTomcatTarball} ${remoteTomcatTarball}
fi

if [[ ! -f ${localImg} ]]; then
  wget -O ${localImg} ${remoteImg}
fi

if [[ ! -f ${localRaw}  ]]; then
  qemu-img convert -O raw ${localImg} ${localRaw}
fi

if [[ ! -f ${localVdi}  ]]; then
  VBoxManage convertdd ${localRaw} ${localVdi}
  VBoxManage modifyhd ${localVdi} --resize 30000
fi



# Prepare the cloud-config volume
cat ./cloud-config.yml.tpl | \
  sed -e 's/{{pubKey}}/'"${pubKeyEscaped}"'/g' | \
  sed -e 's/{{forceHttps}}/false/g' | \
  sed -e 's/{{domain}}/'"${hostIp}"'/g' | \
  sed -e 's/{{httpPort}}/10080/g' | \
  sed -e 's/{{tomcatTarballUrl}}/http:\/\/'"${hostIp}"':8000\/apache-tomcat-8.5.37.tar.gz/g' | \
  sed -e 's/{{aggregateWarUrl}}/http:\/\/'"${hostIp}"':8000\/aggregate.war/g' \
  > cloud-config.yml
cloud-localds ${cloudConfigIso} cloud-config.yml

# Create the VM
vboxmanage createvm --name ${vmName} --register
vboxmanage modifyvm ${vmName} --ioapic on
vboxmanage modifyvm ${vmName} --cpus 4
vboxmanage modifyvm ${vmName} --memory 8196
vboxmanage modifyvm ${vmName} --boot1 disk
vboxmanage modifyvm ${vmName} --acpi on
vboxmanage modifyvm ${vmName} --nic1 nat
vboxmanage modifyvm ${vmName} --natpf1 "ssh,tcp,,10022,,22"
vboxmanage modifyvm ${vmName} --natpf1 "nginx,tcp,,10080,,80"
vboxmanage modifyvm ${vmName} --uart1 0x3F8 4
vboxmanage modifyvm ${vmName} --uartmode1 server my.ttyS0
vboxmanage storagectl ${vmName} --name "IDE_0"  --add ide
vboxmanage storageattach ${vmName} --storagectl "IDE_0" --port 0 --device 0 --type hdd --medium ${localVdi}
vboxmanage storageattach ${vmName} --storagectl "IDE_0" --port 1 --device 0 --type dvddrive --medium ${cloudConfigIso}

echo
echo "Starting the VM"
echo
echo "- You will be able to access Aggregate at http://${hostIp}:10080"
echo "- Stop the VM with the VirtualBox app"
echo "- You don't need to stop the VM to relaunch it"
echo
echo "In another terminal, you can:"
echo "- SSH into the machine with: ssh -p 10022 odk@localhost"
echo

# Serve assets locally
ps a | grep -v grep | grep "python3 -m http.server" > /dev/null
result=$?
if [[ "${result}" -eq "0" ]] ; then
    echo "Already serving local assets"
else
    echo "Serving local assets"
    python3 -m http.server &
fi

# Launch VM
vboxheadless --startvm ${vmName} &

echo "Waiting 5 seconds to link TTY output..."
echo

sleep 5
socat UNIX:my.ttyS0 -



