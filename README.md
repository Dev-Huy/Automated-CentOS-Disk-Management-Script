# Script Tự Động Quản Lý Ổ Đĩa CentOS

![Platform](https://img.shields.io/badge/platform-CentOS%20%7C%20RHEL-262577)
![Shell](https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/license-xem%20LICENSE-blue)

Tiện ích Bash dạng menu giúp chuẩn bị ổ đĩa Linux, tạo vùng lưu trữ LVM, gắn kết hệ thống tệp và cấu hình thư mục chia sẻ Samba cho phép khách truy cập ghi mà không cần mật khẩu.

> [!WARNING]
> Script thực hiện các thao tác ổ đĩa với quyền quản trị. Việc phân vùng, định dạng và khởi tạo LVM có thể xóa dữ liệu vĩnh viễn. Thư mục Samba anonymous cho phép ghi mà không cần mật khẩu, không phù hợp với mạng không đáng tin cậy. Hãy đọc mã nguồn và sao lưu dữ liệu quan trọng trước khi chạy.

## 🧭 Giới thiệu

Dự án cung cấp quy trình tương tác để thực hiện các tác vụ quản lý lưu trữ phổ biến trên CentOS và các hệ thống tương thích với RHEL. Công cụ phù hợp với môi trường thử nghiệm và quản trị viên hiểu rõ rủi ro khi phân vùng ổ đĩa hoặc chia sẻ dữ liệu qua mạng.

Script yêu cầu quyền `root` và hiện sử dụng `yum` để cài đặt gói. Dự án không cung cấp dịch vụ HTTP hay API.

## ✨ Tính năng chính

- Liệt kê thiết bị lưu trữ và từ chối các ổ đĩa được phát hiện là đang gắn kết.
- Tạo một phân vùng chính có dung lượng do người dùng nhập (hoặc dùng phần dung lượng còn lại của ổ đĩa), định dạng bằng ext4, XFS hoặc ext3.
- Chuẩn bị phân vùng kiểu LVM trên ổ đĩa được chọn, sau đó khởi tạo physical volume, volume group và logical volume từ một hay nhiều thiết bị.
- Định dạng logical volume bằng ext4, XFS hoặc ext3 và gắn kết hệ thống tệp.
- Tạo thư mục chia sẻ Samba cho khách truy cập không cần mật khẩu; mở dịch vụ Samba trên firewall nếu `firewalld` đang hoạt động.
- Thử cấu hình quota cho tài khoản `client_user` trên hệ thống tệp không phải XFS.

## 🛠️ Công nghệ sử dụng

- **Bash** cho quy trình dòng lệnh tương tác
- **Công cụ lưu trữ Linux:** `lsblk`, `fdisk`, `partprobe`, `mkfs`, `mount` và `df`
- **LVM2:** `pvcreate`, `vgcreate` và `lvcreate`
- **Samba:** `smb`, `nmb` và `smb.conf`
- **Quota và công cụ quản trị hệ thống:** `quota`, `systemctl`, `firewall-cmd` và tiện ích SELinux

## 🚀 Bắt đầu

### Yêu cầu

- CentOS hoặc bản phân phối Linux tương thích RHEL có `yum` và `systemd`
- Quyền truy cập shell `root` hoặc quyền sử dụng `sudo`
- Một ổ đĩa có thể bị xóa dữ liệu để phân vùng; hoặc một hay nhiều thiết bị khối chưa gắn kết để khởi tạo LVM
- Kết nối mạng từ máy khách đến máy chủ để sử dụng Samba

Khi chạy chức năng Samba, script cài `quota`, `samba`, `samba-client` và `samba-common` bằng `yum`. Các công cụ `lsblk`, `fdisk`, `partprobe`, `mkfs`, `mount`, LVM2, tiện ích SELinux và `firewalld` (nếu dùng firewall) cần có sẵn hoặc được cấu hình phù hợp trên máy chủ. Script không tự cài đặt tất cả các thành phần cần thiết.

### Cài đặt

Clone repository và chuyển vào thư mục dự án:

```bash
git clone https://github.com/Dev-Huy/Automated-CentOS-Disk-Management-Script.git
cd Automated-CentOS-Disk-Management-Script
```

Cấp quyền thực thi cho script:

```bash
chmod +x Automated-CentOS-Disk-Management-Script.sh
```

## 💻 Cách sử dụng

Chạy script với quyền quản trị:

```bash
sudo ./Automated-CentOS-Disk-Management-Script.sh
```

Chọn một chức năng trong menu:

| Lựa chọn | Chức năng |
| --- | --- |
| `1` | Chọn ổ đĩa, nhập dung lượng phân vùng chính (hoặc nhấn Enter để dùng toàn bộ ổ), chọn hệ thống tệp và gắn kết. |
| `2` | Chọn bước 1 để tạo phân vùng kiểu LVM, hoặc bước 2 để chọn một hay nhiều thiết bị chưa gắn kết, tạo PV/VG/LV, định dạng và gắn kết. |
| `3` | Chọn điểm gắn kết hiện có, tạo thư mục chia sẻ và cấu hình Samba anonymous cho phép ghi, không cần mật khẩu. |
| `0` | Thoát chương trình. |

Ở chức năng 1, nhập dung lượng theo định dạng `fdisk` như `+10G` hoặc `+500M`; nhấn Enter để dùng phần dung lượng còn lại. Ở chức năng 2, bước 1 chuẩn bị phân vùng LVM trên một ổ đĩa; sau khi hoàn tất, chạy lại chức năng 2 và chọn bước 2 để đưa phân vùng đó cùng các thiết bị chưa gắn kết khác vào LVM. Bước 2 tạo LV dùng toàn bộ dung lượng trống của VG. Hệ thống tệp thông thường và LVM lần lượt được gắn kết tại `/root/Desktop/DiskLocal` và `/root/Desktop/DiskLVM`.

Chức năng 3 yêu cầu nhập điểm gắn kết đang hoạt động, tên thư mục chia sẻ không chứa khoảng trắng và dung lượng quota tính bằng MB. Sau đó script tạo thư mục con, cấu hình Samba anonymous và cố gắng áp dụng quota cho `client_user` trên ext3/ext4.

Chương trình không có API endpoint; mọi thao tác được thực hiện qua menu trong terminal.

### Lưu ý vận hành quan trọng

- Chức năng 1 và 2 chỉ gắn kết trong phiên hiện tại, không tự thêm cấu hình mount bền vững. Chức năng 3 ghi một mục vào `/etc/fstab` cho điểm gắn kết được chọn với các tùy chọn `usrquota,grpquota`; hãy kiểm tra mục này và cấu hình mount sau khi chạy.
- Chức năng Samba sửa `/etc/samba/smb.conf`, `/etc/fstab`, quyền truy cập tệp, cấu hình SELinux và dịch vụ hệ thống. Script tạo bản sao lưu `smb.conf` nếu tệp sao lưu chưa tồn tại, bật và khởi động lại `smb`/`nmb`, đồng thời mở dịch vụ Samba trên `firewalld` nếu đang hoạt động.
- Thư mục chia sẻ anonymous cho phép khách ghi dữ liệu và sử dụng quyền thư mục rộng. Hãy giới hạn truy cập mạng, không công khai dịch vụ này trên Internet.
- Nhánh XFS chỉ ghi chú rằng cần cấu hình quota riêng; script không áp dụng quota XFS. Với hệ thống tệp khác XFS, quota có thể không hoạt động nếu các tùy chọn mount hoặc công cụ quota chưa được hỗ trợ đúng cách.
- Hãy rà soát script trước khi sử dụng trong môi trường production. Các bước kiểm tra tương tác không thay thế cho kế hoạch sao lưu và khôi phục đã được kiểm thử.

## 📁 Cấu trúc thư mục

```text
.
├── Automated-CentOS-Disk-Management-Script.sh  # Script quản lý lưu trữ và Samba
├── LICENSE                                      # Thông tin giấy phép dự án
└── README.md                                    # Tài liệu dự án
```

## 📄 Giấy phép

Xem tệp [LICENSE](LICENSE) để biết thông tin chi tiết về giấy phép.
