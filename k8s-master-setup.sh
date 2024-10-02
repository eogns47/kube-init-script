#!/bin/bash

# 사용자 추가 및 방화벽 제거
sudo adduser master
sudo bash -c 'cat <<EOF | tee /etc/sudoers.d/sudoers-master
master     ALL=(ALL:ALL)   NOPASSWD:ALL
EOF'

sudo systemctl stop ufw
sudo systemctl disable ufw
sudo systemctl stop apparmor.service
sudo systemctl disable apparmor.service
sudo swapoff -a

# 쿠버네티스 모듈 추가 및 네트워크 포워딩 설정
sudo bash -c 'cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF'

sudo modprobe overlay
sudo modprobe br_netfilter

sudo bash -c 'cat <<EOF | tee /etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF'

sudo sysctl --system
sudo iptables -P FORWARD ACCEPT

# 컨테이너 런타임 설치 (containerd)
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo bash -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null'

sudo apt-get update
sudo apt-get install -y containerd.io
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

# Cgroup은 프로세스에 대한 리소스를 정의할 때 필요 컨테이너 런타임과 쿠블렛이 하나는 systemd를, 하나는 Croupfs를 사용하는 건 불가능
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# crictl 설치
VERSION="v1.30.0"
curl -L https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-${VERSION}-linux-amd64.tar.gz --output crictl-${VERSION}-linux-amd64.tar.gz
sudo tar zxvf crictl-$VERSION-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-$VERSION-linux-amd64.tar.gz

sudo bash -c 'cat <<EOF | tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
EOF'

# kubectl 설치
curl -LO "https://dl.k8s.io/release/v1.30.3/bin/linux/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

# kubernetes 설치
mkdir -p ~/kubeadm && cd ~/kubeadm
sudo bash -c 'curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg'
sudo bash -c 'echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list'

sudo apt-get update
sudo apt-get install -y kubelet="1.30.3-*" kubeadm="1.30.3-*"
sudo systemctl enable --now kubelet

# kubeconfig 설정
mkdir -p ~/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
