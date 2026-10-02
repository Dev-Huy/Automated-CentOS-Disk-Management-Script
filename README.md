# Script quản lý lưu trữ CentOS

![Platform](https://img.shields.io/badge/platform-CentOS%20%7C%20RHEL-262577)
![Shell](https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/license-xem%20LICENSE-blue)

Công cụ Bash tương tác dành cho CentOS 7 để phân vùng và mount ổ đĩa, khởi tạo hoặc mở rộng LVM, cấu hình quota và tạo thư mục chia sẻ Samba.

> [!CAUTION]
> Chạy bằng quyền `root`. Các thao tác phân vùng, định dạng, khởi tạo LVM, sửa `/etc/fstab`, thay đổi quyền tệp và cấu hình dịch vụ có thể làm mất dữ liệu hoặc ảnh hưởng toàn hệ thống. Chỉ chọn đúng thiết bị có vùng trống dự định sử dụng; với ổ chưa có phân vùng, script có thể tạo GPT và partition mới trên ổ đó. Không dựa riêng vào bộ lọc tự động để xác định ổ an toàn. Hãy sao lưu, kiểm tra tên thiết bị và rà soát lệnh trước khi xác nhận.
>
> Chia sẻ Samba được cấu hình cho khách truy cập không cần mật khẩu, cho phép ghi và cấp quyền thư mục rộng (`777`). Chỉ sử dụng trong mạng tin cậy, không phơi dịch vụ ra Internet.

## Tính năng

- Tạo phân vùng mới trong phần dung lượng còn trống được chọn; hỗ trợ ext4, XFS và ext3.
- Tạo PV/VG/LV mới từ một hoặc nhiều thiết bị, hoặc thêm phân vùng mới vào VG/LV hiện có và mở rộng hệ thống tệp.
- Cấu hình quota blocks và inodes cho một tài khoản hệ thống đã tồn tại trên hệ thống tệp không phải XFS.
- Tạo hoặc dùng thư mục chia sẻ Samba, chọn tài khoản đại diện và bật dịch vụ `smb`/`nmb`; chia sẻ cho phép khách ghi.

## Yêu cầu

- CentOS 7 (script dùng `yum` và `systemd`; các bản Linux khác chưa được xác nhận).
- Quyền `root` hoặc `sudo`.
- Các tiện ích hệ thống tương ứng với chức năng sử dụng: `lsblk`, `fdisk`, `partprobe`, `mkfs`, `mount`; `parted` và LVM2 cho chức năng LVM; `blkid`, `findmnt`, `resize2fs`/`xfs_growfs`; quota, Samba và tiện ích SELinux.
- Mạng và cấu hình firewall cho phép máy khách kết nối tới Samba. Script không tự cấu hình firewall.

Script tự cài `quota` khi cấu hình quota và cài `samba`, `samba-client`, `samba-common` khi cấu hình chia sẻ. Các công cụ còn lại cần được cài đặt trên máy chủ trước khi dùng chức năng tương ứng.

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
| `1` | Tạo phân vùng trong vùng trống, chọn ext4/XFS/ext3 và mount. Có thể nhập kích thước như `+10G` hoặc nhấn Enter để dùng phần trống còn lại; có tùy chọn ép định dạng. |
| `2` | Chọn khởi tạo LVM mới hoặc mở rộng VG/LV hiện có bằng vùng trống trên các ổ mới. Khi tạo mới, nhập tên ổ, kích thước cần dùng, tên VG/LV và kích thước LV; để trống kích thước để dùng toàn bộ vùng trống tương ứng. |
| `3` | Chọn mount point, tài khoản hệ thống, rồi đặt giới hạn quota blocks (MB), inodes và tùy chọn grace period. XFS chưa được hỗ trợ bởi chức năng này. |
| `4` | Chọn mount point và thư mục chia sẻ, chọn tài khoản đại diện, sau đó cấu hình Samba guest có quyền ghi. |
| `0` | Thoát. |

Phân vùng mới được mount tại `/root/Desktop/DiskLocal_<partition>`. Logical volume mới được mount tại `/mnt/DiskLVM_<VG>_<LV>`. Khi mount, script thêm cấu hình vào `/etc/fstab` để mount lại sau khi khởi động.

## Tác động hệ thống và giới hạn

- Bộ lọc đĩa của chức năng 1 loại ổ chứa mount point `/` hoặc `/boot`, ổ có từ 4 phân vùng và ổ được ước tính còn dưới 10 MB. Đây chỉ là kiểm tra sơ bộ; nó không xác nhận vùng trống thực sự an toàn.
- Khi chuẩn bị thiết bị cho LVM, script dùng `parted` để tạo phân vùng trong vùng trống. Nếu ổ chưa có phân vùng, script có thể tạo GPT và dùng gần như toàn bộ ổ. Chỉ chọn thiết bị phù hợp; tạo PV/VG mới hoặc định dạng LV có thể phá hủy dữ liệu.
- Mở rộng LVM chạy `pvcreate`, `vgextend`, `lvextend` và tiện ích resize hệ thống tệp. Xác minh các ổ mới, VG, LV và dung lượng trước khi thao tác.
- Hàm mount thêm thiết bị, mount point và filesystem vào `/etc/fstab` nếu chưa có mount point đó. Cấu hình quota thay dòng `/etc/fstab` ứng với mount point bằng tùy chọn `usrquota,grpquota`, remount rồi chạy công cụ quota; rà soát file này sau khi chạy. XFS chỉ được báo cần cấu hình riêng, script không áp dụng quota XFS.
- Cấu hình Samba sửa `/etc/samba/smb.conf` (tạo bản sao `.bak` nếu chưa có), cấp quyền `777` đệ quy cho thư mục chia sẻ, bật guest ghi, thay đổi SELinux, cài gói Samba và bật/khởi động lại `smb`/`nmb`. Script không mở cổng firewall.
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
