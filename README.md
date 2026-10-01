# Script quản lý lưu trữ CentOS và Samba

![Platform](https://img.shields.io/badge/platform-CentOS%20%7C%20RHEL-262577)
![Shell](https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/license-xem%20LICENSE-blue)

Công cụ Bash tương tác để phân vùng ổ đĩa, quản lý LVM, cấu hình quota và tạo thư mục chia sẻ Samba trên CentOS hoặc hệ thống Linux tương thích RHEL.

> [!CAUTION]
> Chạy bằng quyền `root`. Các thao tác phân vùng, định dạng, khởi tạo LVM, thay đổi quyền tệp và cấu hình dịch vụ có thể làm mất dữ liệu hoặc ảnh hưởng toàn hệ thống. Đặc biệt, chức năng chuẩn bị thiết bị cho LVM ghi một partition table mới lên ổ đĩa được chọn; không chọn ổ đang chứa dữ liệu cần giữ. Hãy kiểm tra mã nguồn, sao lưu và xác minh tên thiết bị trước khi thao tác.
>
> Chia sẻ Samba được cấu hình cho khách truy cập không cần mật khẩu, cho phép ghi và cấp quyền thư mục rộng (`777`). Chỉ sử dụng trong mạng tin cậy, không phơi dịch vụ ra Internet.

## Tính năng

- Tạo phân vùng mới trên ổ đĩa được script nhận diện là còn chỗ trống; hỗ trợ ext4, XFS và ext3.
- Tạo PV/VG/LV mới từ một hoặc nhiều thiết bị, hoặc thêm thiết bị mới vào VG/LV hiện có và mở rộng hệ thống tệp.
- Cấu hình quota blocks và inodes cho một tài khoản hệ thống đã tồn tại trên hệ thống tệp không phải XFS.
- Tạo hoặc dùng thư mục chia sẻ Samba, chọn tài khoản đại diện và bật dịch vụ `smb`/`nmb`.

## Yêu cầu

- CentOS hoặc Linux tương thích RHEL với Bash, `yum` và `systemd`.
- Quyền `root` hoặc `sudo`.
- Các tiện ích hệ thống tương ứng với chức năng sử dụng: `lsblk`, `fdisk`, `partprobe`, `mkfs`, `mount`, LVM2, `blkid`, `findmnt`, `resize2fs`/`xfs_growfs`, quota, Samba và tiện ích SELinux.
- Mạng và cấu hình firewall cho phép máy khách kết nối tới Samba. Script không tự cấu hình firewall.

Script tự cài `quota` khi cấu hình quota và cài `samba`, `samba-client`, `samba-common` khi cấu hình chia sẻ. Các công cụ còn lại cần được cài đặt và cấu hình phù hợp trên máy chủ.

## Cài đặt

```bash
git clone https://github.com/Dev-Huy/Automated-CentOS-Disk-Management-Script.git
cd Automated-CentOS-Disk-Management-Script
chmod +x Automated-CentOS-Disk-Management-Script.sh
sudo ./Automated-CentOS-Disk-Management-Script.sh
```

## Sử dụng

Menu chính:

| Lựa chọn | Chức năng |
| --- | --- |
| `1` | Tạo phân vùng, chọn ext4/XFS/ext3 và mount phân vùng. Có thể nhập kích thước như `+10G` hoặc nhấn Enter để dùng phần trống còn lại. |
| `2` | Tạo LVM mới hoặc mở rộng VG/LV hiện có bằng thiết bị mới. Khi tạo mới, nhập tên ổ đĩa, tên VG và tên LV; LV mới dùng toàn bộ dung lượng trống. |
| `3` | Chọn mount point, tài khoản hệ thống, rồi đặt giới hạn quota blocks (MB), inodes và tùy chọn grace period. XFS chưa được hỗ trợ bởi chức năng này. |
| `4` | Chọn mount point và thư mục chia sẻ, chọn tài khoản đại diện, sau đó cấu hình Samba guest có quyền ghi. |
| `0` | Thoát. |

Các phân vùng mới được mount tại `/root/Desktop/DiskLocal_<partition>`. Logical volume mới được mount tại `/root/Desktop/DiskLVM_<VG>_<LV>`. Script không tự ghi các mount point này vào `/etc/fstab`.

## Tác động hệ thống và giới hạn

- Bộ lọc đĩa của chức năng 1 loại ổ chứa mount point `/` hoặc `/boot`, ổ có từ 4 phân vùng và ổ được ước tính còn dưới 10 MB. Đây là kiểm tra đơn giản, không thay thế việc tự xác minh thiết bị và dữ liệu.
- Khi chuẩn bị ổ cho LVM, script dùng `fdisk` để tạo partition table mới và phân vùng LVM số 1. Thao tác này có thể phá hủy các phân vùng cũ trên thiết bị đã chọn.
- Mở rộng LVM chạy `pvcreate`, `vgextend`, `lvextend` và tiện ích resize hệ thống tệp trên các thiết bị/LV được chọn. Kiểm tra VG, LV và tên thiết bị trước khi xác nhận.
- Cấu hình quota sửa `/etc/fstab` cho mount point đã nhập, remount với `usrquota,grpquota`, rồi chạy các công cụ quota. XFS chỉ được báo cần cấu hình riêng; script không áp dụng quota XFS.
- Cấu hình Samba sửa `/etc/samba/smb.conf` (tạo bản sao `.bak` nếu chưa có), thay đổi quyền thư mục và SELinux, cài gói Samba, bật và khởi động lại `smb`/`nmb`. Script không mở cổng firewall.
- Quota và Samba yêu cầu mount point đang được mount. Các thay đổi hệ thống có thể cần rà soát hoặc hoàn tác thủ công.

Đây là tiện ích quản trị tương tác, không phải dịch vụ HTTP/API. Hãy thử trong máy ảo hoặc môi trường không chứa dữ liệu quan trọng trước khi sử dụng trên máy thật.

## Cấu trúc

```text
.
├── Automated-CentOS-Disk-Management-Script.sh
├── LICENSE
└── README.md
```

## Giấy phép

Xem [LICENSE](LICENSE) để biết thông tin giấy phép.