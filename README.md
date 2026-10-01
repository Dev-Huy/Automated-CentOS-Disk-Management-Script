# Automated CentOS Disk Management Script

![Platform](https://img.shields.io/badge/platform-CentOS%20%7C%20RHEL-262577)
![Shell](https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/license-see%20LICENSE-blue)

A menu-driven Bash utility for preparing Linux disks, creating LVM storage, mounting filesystems, and configuring writable anonymous Samba shares.

> [!WARNING]
> This script performs privileged disk operations. Partitioning, formatting, and LVM initialization can permanently destroy data. Anonymous Samba shares are writable without a password and are not suitable for untrusted networks. Review the script and back up important data before running it.

## 🧭 About the Project

The project provides an interactive workflow for common storage administration tasks on CentOS and compatible RHEL-based systems. It is intended for lab environments and administrators who understand the implications of partitioning disks and exposing network shares.

The script requires root privileges and currently uses `yum` for package installation. It does not provide an HTTP service or API.

## ✨ Key Features

- Lists block devices and rejects selected disks that appear to be mounted.
- Creates a 10 GiB primary partition and formats it as ext4, XFS, or ext3.
- Creates an LVM-ready partition layout on a selected disk.
- Builds an LVM physical volume, volume group, and logical volume from selected devices.
- Mounts standard and LVM filesystems under `/root/Desktop`.
- Configures a writable guest Samba share and opens the Samba firewall service when `firewalld` is active.
- Attempts to configure user quota for non-XFS filesystems.

## 🛠️ Built With

- **Bash** for the interactive command-line workflow
- **Linux storage tools:** `lsblk`, `fdisk`, `partprobe`, `mkfs`, `mount`, and `df`
- **LVM2:** `pvcreate`, `vgcreate`, and `lvcreate`
- **Samba:** `smb`, `nmb`, and `smb.conf`
- **Quota and system administration tools:** `quota`, `systemctl`, `firewall-cmd`, and SELinux utilities

## 🚀 Getting Started

### Prerequisites

- CentOS or a compatible RHEL-based Linux distribution with `yum` and `systemd`
- A root shell or `sudo` access
- A spare, unmounted disk for partitioning, or unmounted block devices for LVM
- Network access from clients to the host for Samba usage

The script installs quota and Samba packages through `yum` when those features are selected. Disk utilities, LVM2, SELinux tools, and `firewalld` should be installed and configured as appropriate for the host. The script does not install every prerequisite automatically.

### Installation

Clone the repository and enter its directory:

```bash
git clone <repository-url>
cd <repository-directory>
```

Make the script executable:

```bash
chmod +x Automated-CentOS-Disk-Management-Script.sh
```

Replace the placeholders above with the URL and directory name of your repository.

## 💻 Usage

Run the script as root:

```bash
sudo ./Automated-CentOS-Disk-Management-Script.sh
```

Choose an option from the interactive menu:

| Menu option | Operation |
| --- | --- |
| `1` | Select a disk and create either a 10 GiB formatted primary partition or an LVM-ready partition layout. |
| `2` | Select unmounted block devices, create an LVM volume, format it, and mount it. |
| `3` | Select an existing mount point, create a share directory, and configure an anonymous writable Samba share. |
| `0` | Exit. |

For partitioning, verify the selected device carefully and confirm only when you intend to erase or reconfigure it. For LVM, use only devices whose contents can be overwritten. The standard and LVM workflows mount their filesystems at `/root/Desktop/DiskLocal` and `/root/Desktop/DiskLVM`, respectively. Selecting the Samba option prompts for an existing mount point, share name, and quota size.

There are no API endpoints; all interaction is through the script's terminal menu.

### Important operational notes

- The script does not consistently configure the standard and LVM mount points for automatic mounting after reboot. Verify `/etc/fstab` and your system's mount configuration before relying on persistent mounts.
- The Samba workflow modifies `/etc/samba/smb.conf`, `/etc/fstab`, file permissions, SELinux settings, and system services. It creates a backup of `smb.conf` if one does not already exist.
- The anonymous share grants guest write access and uses permissive directory modes. Restrict network access and do not expose it to the public internet.
- The script's XFS branch explicitly skips quota setup; configure XFS quotas separately if required.
- Review the script before production use. Its interactive checks do not replace a tested backup and recovery plan.

## 📁 Directory Structure

```text
.
├── Automated-CentOS-Disk-Management-Script.sh  # Interactive storage and Samba utility
├── LICENSE                                      # Project license
└── README.md                                    # Project documentation
```

## 📄 License

See the [LICENSE](LICENSE) file for license details.
