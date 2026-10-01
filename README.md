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
- Tạo phân vùng chính 10 GiB và định dạng bằng ext4, XFS hoặc ext3.
- Tạo bố cục phân vùng sẵn sàng sử dụng với LVM trên ổ đĩa được chọn.
- Tạo physical volume, volume group và logical volume LVM từ các thiết bị được chọn.
- Gắn kết hệ thống tệp thông thường và LVM bên dưới `/root/Desktop`.
- Cấu hình thư mục Samba cho khách truy cập ghi và mở dịch vụ Samba trên firewall nếu `firewalld` đang hoạt động.
- Thử cấu hình quota người dùng cho hệ thống tệp không phải XFS.

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
- Một ổ đĩa trống, chưa gắn kết để phân vùng; hoặc các thiết bị khối chưa gắn kết để dùng với LVM
- Kết nối mạng từ máy khách đến máy chủ để sử dụng Samba

Khi chọn các tính năng liên quan, script sẽ cài các gói quota và Samba bằng `yum`. Các tiện ích ổ đĩa, LVM2, công cụ SELinux và `firewalld` cần được cài đặt, cấu hình phù hợp trên máy chủ. Script không tự cài đặt tất cả các thành phần cần thiết.

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
| `1` | Chọn ổ đĩa và tạo phân vùng chính 10 GiB đã định dạng hoặc bố cục phân vùng sẵn sàng cho LVM. |
| `2` | Chọn thiết bị khối chưa gắn kết, tạo logical volume LVM, định dạng và gắn kết. |
| `3` | Chọn điểm gắn kết hiện có, tạo thư mục chia sẻ và cấu hình Samba anonymous cho phép ghi, không cần mật khẩu. |
| `0` | Thoát chương trình. |

Khi phân vùng, hãy kiểm tra kỹ thiết bị đã chọn và chỉ xác nhận nếu bạn chủ ý xóa hoặc cấu hình lại thiết bị đó. Với LVM, chỉ chọn thiết bị có thể bị ghi đè dữ liệu. Quy trình thông thường và LVM lần lượt gắn kết hệ thống tệp tại `/root/Desktop/DiskLocal` và `/root/Desktop/DiskLVM`. Chức năng Samba yêu cầu nhập điểm gắn kết có sẵn, tên thư mục chia sẻ và dung lượng quota.

Chương trình không có API endpoint; mọi thao tác được thực hiện qua menu trong terminal.

### Lưu ý vận hành quan trọng

- Script không cấu hình nhất quán để các điểm gắn kết thông thường và LVM tự động mount sau khi khởi động lại. Hãy kiểm tra `/etc/fstab` và cấu hình mount của hệ thống trước khi dựa vào mount bền vững.
- Quy trình Samba sửa `/etc/samba/smb.conf`, `/etc/fstab`, quyền truy cập tệp, cấu hình SELinux và dịch vụ hệ thống. Script tạo bản sao lưu `smb.conf` nếu tệp sao lưu chưa tồn tại.
- Thư mục chia sẻ anonymous cho phép khách ghi dữ liệu và sử dụng quyền thư mục rộng. Hãy giới hạn truy cập mạng, không công khai dịch vụ này trên Internet.
- Nhánh XFS của script bỏ qua thiết lập quota; nếu cần quota cho XFS, hãy cấu hình riêng.
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
