
#!/usr/bin/env bash

ccpe_path="$PWD"

# Install prerequisite packages for an RHEL Hyperledger build
prereq_rhel() {
  echo -e "\nInstalling RHEL prerequisite packages\n"
  yum -y -q install git gcc gcc-c++ wget tar python-setuptools python-devel device-mapper libtool-ltdl-devel libffi-devel openssl-devel
  if [ $? != 0 ]; then
    echo -e "\nERROR: Unable to install pre-requisite packages.\n"
    exit 1
  fi
  if [ ! -f /usr/bin/s390x-linux-gnu-gcc ]; then
    ln -s /usr/bin/s390x-redhat-linux-gcc /usr/bin/s390x-linux-gnu-gcc
  fi
}

# Install prerequisite packages for an SLES Hyperledger build
prereq_sles() {
  echo -e "\nInstalling SLES prerequisite packages\n"
  zypper --non-interactive in git-core gcc make gcc-c++ patterns-sles-apparmor  python-setuptools python-devel libtool libffi48-devel libopenssl-devel
  if [ $? != 0 ]; then
    echo -e "\nERROR: Unable to install pre-requisite packages.\n"
    exit 1
  fi
  if [ ! -f /usr/bin/s390x-linux-gnu-gcc ]; then
    ln -s /usr/bin/gcc /usr/bin/s390x-linux-gnu-gcc
  fi
}

# Install prerequisite packages for an Unbuntu Hyperledger build
prereq_ubuntu() {
  echo -e "\nInstalling Ubuntu prerequisite packages\n"
  apt-get update
  apt-get -y install build-essential git debootstrap python-setuptools python-dev alien libtool libffi-dev libssl-dev
  if [ $? != 0 ]; then
    echo -e "\nERROR: Unable to install pre-requisite packages.\n"
    exit 1
  fi
}

# Determine flavor of Linux OS
get_linux_flavor() {
  OS_FLAVOR=`cat /etc/os-release | grep ^NAME | sed -r 's/.*"(.*)"/\1/'`

  if grep -iq 'red' <<< $OS_FLAVOR; then
    OS_FLAVOR="rhel"
  elif grep -iq 'sles' <<< $OS_FLAVOR; then
    OS_FLAVOR="sles"
  elif grep -iq 'ubuntu' <<< $OS_FLAVOR; then
    OS_FLAVOR="ubuntu"
  else
    echo -e "\nERROR: Unsupported Linux Operating System.\n"
    exit 1
  fi
}
# Build and install the Docker Daemon
install_docker() {
  echo -e "\n*** install_docker ***\n"

  # Setup Docker for RHEL or SLES
  if [ $1 == "rhel" ]; then
    DOCKER_URL="ftp://ftp.unicamp.br/pub/linuxpatch/s390x/redhat/rhel7.2/docker-1.11.2-rhel7.2-20160623.tar.gz"
    DOCKER_DIR="docker-1.11.2-rhel7.2-20160623"

    # Install Docker
    cd /tmp
    wget -q $DOCKER_URL
    if [ $? != 0 ]; then
      echo -e "\nERROR: Unable to download the Docker binary tarball.\n"
      exit 1
    fi
    tar -xzf $DOCKER_DIR.tar.gz
    if [ -f /usr/bin/docker ]; then
      mv /usr/bin/docker /usr/bin/docker.orig
    fi
    cp $DOCKER_DIR/docker* /usr/bin

    # Setup Docker Daemon service
    if [ ! -d /etc/docker ]; then
      mkdir -p /etc/docker
    fi

    # Create environment file for the Docker service
    touch /etc/docker/docker.conf
    chmod 664 /etc/docker/docker.conf
    echo 'DOCKER_OPTS="-H tcp://0.0.0.0:2375 -H unix:///var/run/docker.sock -s overlay"' >> /etc/docker/docker.conf
    touch /etc/systemd/system/docker.service
    chmod 664 /etc/systemd/system/docker.service

    # Create Docker service file
    cat > /etc/systemd/system/docker.service <<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
[Service]
Type=notify
ExecStart=/usr/bin/docker daemon \$DOCKER_OPTS
EnvironmentFile=-/etc/docker/docker.conf
[Install]
WantedBy=default.target
EOF
    # Start Docker Daemon
    systemctl daemon-reload
    systemctl enable docker.service
    systemctl start docker.service
  elif [ $1 == "sles" ]; then
    zypper --non-interactive in docker
    systemctl stop docker.service
    sed -i '/^DOCKER_OPTS/ s/\"$/ \-H tcp\:\/\/0\.0\.0\.0\:2375\"/' /etc/sysconfig/docker
    systemctl enable docker.service
    systemctl start docker.service
  else      # Setup Docker for Ubuntu
    apt-get -y install docker.io
    systemctl stop docker.service
    sed -i "\$aDOCKER_OPTS=\"-H tcp://0.0.0.0:2375 -H unix:///var/run/docker.sock\"" /etc/default/docker
    systemctl enable docker.service
    systemctl start docker.service
  fi

  cd /tmp
  curl -s "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py"
  python get-pip.py > /dev/null 2>&1
  
  pip install docker-compose
  
  echo -e "*** DONE ***\n"
}

# Determine Linux distribution
get_linux_flavor

# Install pre-reqs for detected Linux OS Distribution
prereq_$OS_FLAVOR

if ! docker images > /dev/null 2>&1; then
  install_docker $OS_FLAVOR
  # Cleanup files and Docker images and containers
  rm -rf /tmp/*

  echo -e "Cleanup Docker artifacts\n"
    # Delete any temporary Docker containers created during the build process
    if [[ ! -z $(docker ps -aq) ]]; then
        docker rm -f $(docker ps -aq)
    fi

  echo -e "\n\nDocker and its supporting components have been successfully installed.\n"
fi

cd "$ccpe_path"

docker stop $(docker ps -a -q)
docker rm -f $(docker ps -a -q)
docker rmi -f $(docker images -q)


cd app-hyperledger
. setenv.sh

#docker-compose -f single-peer-ca.yaml up -d

docker-compose -f four-peer-ca.yaml up -d

cd ../app-webservice
#cd app-webservice
docker build -t ccpe/ws .

# docker network connect bridge apphyperledger_vp0_1
# docker network connect bridge apphyperledger_vp0_2
# docker network connect bridge apphyperledger_vp0_3
# docker network connect bridge apphyperledger_vp0_4

docker network connect bridge apphyperledger_vp0_1
docker network connect bridge apphyperledger_vp1_1
docker network connect bridge apphyperledger_vp2_1
docker network connect bridge apphyperledger_vp3_1

#docker run -p 9999:3000 -d ccpe/ws
docker run --name ccpe_node --net=bridge -p 9999:3000 ccpe/ws