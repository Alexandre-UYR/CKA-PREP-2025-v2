#!/bin/bash
set -e

# Download the CRI Dockerd Debian package to /root, matching typical exam setup.
# The download is skipped if the file is already there, so the setup is safe to
# run again.
DEB=/root/cri-dockerd.deb
if [ ! -s "$DEB" ]; then
  wget https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.20/cri-dockerd_0.3.20.3-0.debian-bullseye_amd64.deb -O "$DEB"
fi

echo "CRI Dockerd package downloaded to $DEB"
echo
echo "The candidate installs it with dpkg, enables and starts cri-docker.service,"
echo "and sets the four sysctls the task lists."
