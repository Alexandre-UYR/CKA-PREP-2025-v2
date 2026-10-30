#!/bin/bash
set -uo pipefail

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

# Stop and disable the service.
$SUDO systemctl disable --now cri-docker.service >/dev/null 2>&1 || true

# Remove the package. The pre-state had only the downloaded .deb, not an
# installed package, so a faithful reset removes it again.
$SUDO dpkg --purge cri-dockerd >/dev/null 2>&1 || true

# Remove the persisted sysctl settings.
$SUDO rm -f /etc/sysctl.d/kube.conf

# Remove the downloaded package file.
rm -f /root/cri-dockerd.deb

echo "Q9 reset"
echo "NOTE: the four sysctl values are still live in this boot's kernel. They reset"
echo "      to their defaults when the machine reboots, since /etc/sysctl.d/kube.conf is gone."
