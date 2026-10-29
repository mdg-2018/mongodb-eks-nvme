#!/bin/bash
sudo mkfs.xfs /dev/nvme1n1
sudo mkdir -p /opt/local-path-provisioner
sudo mount /dev/nvme1n1 /opt/local-path-provisioner
echo "/dev/nvme1n1 /opt/local-path-provisioner xfs defaults 0 0" | sudo tee -a /etc/fstab