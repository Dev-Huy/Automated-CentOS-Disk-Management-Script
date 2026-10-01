#!/bin/bash
# ==========================================================
# SCRIPT QUẢN LÝ LƯU TRỮ VÀ SHARE DISK (BẢN HOÀN THIỆN)
# Kiến trúc: Độc lập - Module hóa - Phân quyền Anonymous
# ==========================================================

if [ "$EUID" -ne 0 ]; then
    echo "Hãy chạy script bằng quyền root (sudo ./quan_ly_centos_samba.sh)"
    exit 1
fi

DISK=""
TEST_USER="client_user"

# ==========================================================
# 1. NHÓM HÀM PARTITION (Tạo đĩa dùng ngay, Format & Mount)
# ==========================================================
chon_o_dia() {
    echo
    echo "=== Danh sach o dia ==="
    lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT
    echo
    read -r -p "Nhap ten o dia can dung (vd: sdb): " name
    DISK="/dev/$name"
    if [ ! -b "$DISK" ]; then
        echo "Khong tim thay $DISK"
        DISK=""
        return 1
    fi
    if lsblk -nr -o MOUNTPOINT "$DISK" | grep -q '[^[:space:]]'; then
        echo "TU CHOI: $DISK dang duoc mount (co the la o chua he dieu hanh)."
        DISK=""
        return 1
    fi
    echo "Da chon: $DISK"
}

chay_chuc_nang_partition() {
    echo "=== TẠO PHÂN VÙNG LƯU TRỮ TIÊU CHUẨN ==="
    chon_o_dia || return 1
    local MOUNT_DIR="/root/Desktop/DiskLocal"
    
    echo "CẢNH BÁO: Mọi dữ liệu trên $DISK sẽ bị XÓA."
    read -r -p "Tiếp tục? (y/N): " ok
    [ "$ok" != "y" ] && [ "$ok" != "Y" ] && { echo "Đã hủy."; return 0; }

    # 1. Thiết lập dung lượng
    echo "--> CẤU HÌNH DUNG LƯỢNG:"
    read -r -p "Nhập dung lượng (vd: +10G, +500M) hoặc nhấn Enter để dùng toàn bộ ổ đĩa: " PART_SIZE

    # 2. Chọn định dạng
    echo "--> CHỌN LOẠI ĐỊNH DẠNG:"
    echo "  1. ext4 (Khuyến nghị)"
    echo "  2. xfs"
    echo "  3. ext3"
    read -r -p "Chọn [1-3]: " fs_choice

    echo "--> Đang tạo phân vùng Primary dung lượng ${PART_SIZE:-TOÀN BỘ} trên $DISK"
    printf "o\nn\np\n1\n\n%s\nw\n" "$PART_SIZE" | fdisk "$DISK" >/dev/null 2>&1
    partprobe "$DISK" 2>/dev/null
    sleep 2

    # KIỂM TRA: Phân vùng có thực sự được tạo ra không?
    if [ ! -b "${DISK}1" ]; then
        echo "=> [LỖI] Không thể tạo phân vùng ${DISK}1 (có thể do nhập sai dung lượng). Đã dừng lại!"
        return 1
    fi

    local FS_TYPE
    case "$fs_choice" in
        2) FS_TYPE="xfs" ;;
        3) FS_TYPE="ext3" ;;
        *) FS_TYPE="ext4" ;;
    esac

    echo "--> Format $FS_TYPE cho ${DISK}1"
    # KIỂM TRA: Lệnh format
    mkfs -t "$FS_TYPE" "${DISK}1" || { echo "=> [LỖI] Quá trình Format thất bại!"; return 1; }

    # KIỂM TRA: Lệnh tạo thư mục và mount
    mkdir -p "$MOUNT_DIR" || { echo "=> [LỖI] Không thể tạo thư mục $MOUNT_DIR"; return 1; }
    mount "${DISK}1" "$MOUNT_DIR" || { echo "=> [LỖI] Không thể gắn kết (Mount) phân vùng vào thư mục!"; return 1; }

    echo "[OK] Đã gắn kết ${DISK}1 vào $MOUNT_DIR."
    echo "=> Ổ đĩa đã sẵn sàng để sử dụng hoặc chia sẻ qua Chức năng 3."
}

# ==========================================================
# 2. HÀM LVM (Chuẩn bị nguyên liệu, Tạo ổ ảo, Format & Mount)
# ==========================================================
setup_lvm() {
    echo "=== QUẢN LÝ Ổ ĐĨA ẢO LVM ==="
    echo " 1. Bước 1: Chuẩn bị đĩa thô (Tạo phân vùng LVM - type 8e)"
    echo " 2. Bước 2: Khởi tạo LVM (Tạo VG, LV, Format & Tự động Mount)"
    read -r -p "Chọn thao tác [1-2]: " lvm_step

    if [ "$lvm_step" == "1" ]; then
        chon_o_dia || return 1
        echo "--> CẤU HÌNH DUNG LƯỢNG CHO PHÂN VÙNG LVM:"
        read -r -p "Nhập dung lượng (vd: +10G, +500M) hoặc nhấn Enter để dùng toàn bộ: " PART_SIZE
        
        echo "CẢNH BÁO: Mọi dữ liệu trên $DISK sẽ bị XÓA."
        read -r -p "Tiếp tục? (y/N): " ok
        [ "$ok" != "y" ] && [ "$ok" != "Y" ] && { echo "Đã hủy."; return 0; }

        echo "--> Đang tạo phân vùng Extended và Logical (type 8e) dung lượng ${PART_SIZE:-TOÀN BỘ} trên $DISK"
        printf "o\nn\ne\n1\n\n%s\nn\nl\n\n\nt\n5\n8e\nw\n" "$PART_SIZE" | fdisk "$DISK" >/dev/null 2>&1
        partprobe "$DISK" 2>/dev/null
        sleep 2
        
        # KIỂM TRA: Phân vùng ảo 8e có được tạo không?
        if [ ! -b "${DISK}5" ]; then
            echo "=> [LỖI] Không thể tạo phân vùng LVM ${DISK}5. Vui lòng kiểm tra lại!"
            return 1
        fi
        
        echo "[OK] Phân vùng ${DISK}5 (type 8e) đã được tạo thành công."
        echo "=> Hãy tiếp tục chọn lại Chức năng 2 (Bước 2) để gộp phân vùng này vào hệ thống LVM."
        return 0
        
    elif [ "$lvm_step" == "2" ]; then
        local -a DEVICES
        local DEV VG_NAME LV_NAME CONFIRM FS_TYPE
        local MOUNT_DIR="/root/Desktop/DiskLVM"
        
        echo "=== KHỞI TẠO VÀ GẮN KẾT LVM ==="
        echo "--> Danh sách các thiết bị/phân vùng KHẢ DỤNG (Gồm cả các phân vùng 8e vừa tạo):"
        echo -e "THIẾT BỊ\tLOẠI\t\tKÍCH THƯỚC"
        
        # Quét lấy ổ đĩa hoặc phân vùng thô chưa bị mount
        lsblk -l -o NAME,TYPE,SIZE,MOUNTPOINT | awk '$4 == "" && ($2 == "disk" || $2 == "part") {printf "/dev/%-15s %-15s %s\n", $1, $2, $3}'
        echo "--------------------------------------------------------"
        
        read -r -p "Nhập thiết bị từ bảng trên (cách nhau bằng khoảng trắng, vd: /dev/sdb5 /dev/sdc): " -a DEVICES
        
        [ "${#DEVICES[@]}" -eq 0 ] && { echo "=> LỖI: Chưa nhập thiết bị nào."; return 1; }
        
        for DEV in "${DEVICES[@]}"; do
            if [ ! -b "$DEV" ]; then
                echo "=> LỖI: Thiết bị $DEV không tồn tại."
                return 1
            fi
            if lsblk -nr -o MOUNTPOINT "$DEV" | grep -q '[^[:space:]]'; then
                echo "=> LỖI: Thiết bị $DEV đang được mount! Không thể dùng."
                return 1
            fi
        done

        read -r -p "Tên Volume Group [VolumeA]: " VG_NAME
        VG_NAME="${VG_NAME:-VolumeA}"
        read -r -p "Tên Logical Volume [LV]: " LV_NAME
        LV_NAME="${LV_NAME:-LV}"

        read -r -p "Tạo LVM ($VG_NAME/$LV_NAME) bằng các thiết bị trên? (y/N): " CONFIRM
        [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ] && return 0

        echo "--> Đang khởi tạo LVM..."
        pvcreate "${DEVICES[@]}" || { echo "=> [LỖI] pvcreate thất bại!"; return 1; }
        vgcreate "$VG_NAME" "${DEVICES[@]}" || { echo "=> [LỖI] vgcreate thất bại!"; return 1; }
        lvcreate -l 100%FREE -n "$LV_NAME" "$VG_NAME" || { echo "=> [LỖI] lvcreate thất bại!"; return 1; }

        local LV_TARGET="/dev/$VG_NAME/$LV_NAME"
        
        echo "Chọn hệ tập tin để format LVM:"
        echo "  1. ext4 (Khuyến nghị) | 2. xfs | 3. ext3"
        read -r -p "Chọn định dạng [1]: " fs_choice_lvm
        
        case "$fs_choice_lvm" in
            2) FS_TYPE="xfs" ;;
            3) FS_TYPE="ext3" ;;
            *) FS_TYPE="ext4" ;;
        esac

        echo "--> Định dạng $FS_TYPE cho $LV_TARGET..."
        mkfs -t "$FS_TYPE" "$LV_TARGET" || { echo "=> [LỖI] Format ổ ảo LVM thất bại!"; return 1; }
        
        mkdir -p "$MOUNT_DIR" || { echo "=> [LỖI] Không thể tạo thư mục $MOUNT_DIR"; return 1; }
        mount "$LV_TARGET" "$MOUNT_DIR" || { echo "=> [LỖI] Không thể gắn kết (Mount) LVM!"; return 1; }
        
        echo "[OK] Ổ ảo LVM $LV_TARGET đã được mount tại $MOUNT_DIR."
        echo "=> Sẵn sàng sử dụng hoặc dùng Chức năng 3 để cấu hình File Server."
    else
        echo "Lựa chọn không hợp lệ."
        return 1
    fi
}

# ==========================================================
# 3. HÀM SHARE DISK (Quét Mount, Tạo Thư Mục Con, Share Anonymous)
# ==========================================================
setup_anonymous_samba_quota() {
    local MOUNT_DIR SHARE_DIR SHARE_PATH TARGET_DEV CURRENT_FS QUOTA_MB
    local SMB_CONF="/etc/samba/smb.conf" 
    
    echo "=== QUÉT VÀ CẤU HÌNH CHIA SẺ FILE SERVER ==="
    
    # 1. Quét các ổ đĩa đã mount sẵn trên hệ thống
    echo "--> Danh sách các ổ đĩa đã được gắn kết (Mount) hợp lệ:"
    echo -e "THIẾT BỊ\t\tHỆ TẬP TIN\tTHƯ MỤC GỐC (MOUNT POINT)"
    df -h -T | grep -E 'ext3|ext4|xfs' | awk '{printf "%-20s %-15s %s\n", $1, $2, $7}'
    echo "--------------------------------------------------------"

    read -r -p "Nhập THƯ MỤC GỐC từ bảng trên (vd: /root/Desktop/DiskLocal): " MOUNT_DIR
    
    if ! mountpoint -q "$MOUNT_DIR"; then
        echo "=> LỖI: $MOUNT_DIR chưa được mount! Hãy dùng Chức năng 1 hoặc 2 để khởi tạo ổ đĩa."
        return 1
    fi

    read -r -p "Nhập tên Thư mục con muốn TẠO để chia sẻ mạng (vd: PublicData): " SHARE_DIR
    read -r -p "Nhập giới hạn Quota (MB) cho toàn bộ ổ đĩa: " QUOTA_MB

    if [ -z "$SHARE_DIR" ] || [[ "$SHARE_DIR" == *" "* ]]; then
        echo "=> LỖI: Tên thư mục chia sẻ không được để trống và không chứa khoảng trắng!"
        return 1
    fi

    TARGET_DEV=$(df "$MOUNT_DIR" | tail -1 | awk '{print $1}')
    CURRENT_FS=$(df -T "$MOUNT_DIR" | tail -1 | awk '{print $2}')

    # 2. Tạo thư mục con & Phân quyền Anonymous
    SHARE_PATH="$MOUNT_DIR/$SHARE_DIR"
    echo "--> Đang tạo và phân quyền cho không gian chia sẻ: $SHARE_PATH"
    
    # KIỂM TRA: Tạo thư mục chia sẻ
    mkdir -p "$SHARE_PATH" || { echo "=> [LỖI] Không thể tạo thư mục chia sẻ!"; return 1; }
    chmod -R 777 "$SHARE_PATH" || { echo "=> [LỖI] Lỗi khi cấp quyền 777 cho thư mục!"; return 1; }
    chcon -Rt samba_share_t "$SHARE_PATH" 2>/dev/null

    # 3. Cập nhật Quota trên ổ đĩa đã mount
    echo "--> Đang áp dụng Quota..."
    yum install -y quota &>/dev/null
    id "$TEST_USER" &>/dev/null || useradd "$TEST_USER"

    sed -i "\|[[:space:]]$MOUNT_DIR[[:space:]]|d" /etc/fstab
    echo "$TARGET_DEV $MOUNT_DIR $CURRENT_FS defaults,usrquota,grpquota 0 0" >> /etc/fstab
    
    # Cảnh báo nếu không thể remount thay vì dừng hẳn script
    mount -o remount,usrquota,grpquota "$MOUNT_DIR" || echo "=> [CẢNH BÁO] Không thể remount ổ đĩa để ép Quota. Tiếp tục cấu hình Samba..."

    if [[ "$CURRENT_FS" != "xfs" ]]; then
        quotacheck -cugm "$MOUNT_DIR" 2>/dev/null
        quotaon -v "$MOUNT_DIR" 2>/dev/null
        
        # Tự động quy đổi MB sang KB và thiết lập Hard Limit
        local QUOTA_KB=$((QUOTA_MB * 1024))
        local QUOTA_HARD=$((QUOTA_KB + 51200)) 
        setquota -u "$TEST_USER" "$QUOTA_KB" "$QUOTA_HARD" 0 0 "$MOUNT_DIR" 2>/dev/null
    else
        echo "(Hệ tập tin XFS: Bỏ qua quotacheck, cần dùng xfs_quota thủ công)"
    fi

    # 4. Ghi cấu hình Samba Anonymous
    echo "--> Đang cấu hình dịch vụ Samba (Quyền Anonymous)..."
    yum install -y samba samba-client samba-common &>/dev/null
    
    # Mở quyền cho thư mục cha để Samba truy cập xuyên qua
    chmod o+x /root 2>/dev/null
    [ -d /root/Desktop ] && chmod o+x /root/Desktop
    chmod o+x "$MOUNT_DIR" 2>/dev/null

    cp -n "$SMB_CONF" "${SMB_CONF}.bak"
    grep -q "map to guest" "$SMB_CONF" || sed -i '/^\[global\]/a\        map to guest = Bad User\n        security = user' "$SMB_CONF"

    # Xóa block cấu hình cũ nếu trùng tên
    sed -i "/^\[$SHARE_DIR\]/,/^# END $SHARE_DIR/d" "$SMB_CONF"
    
    cat >> "$SMB_CONF" <<EOF
[$SHARE_DIR]
# BEGIN $SHARE_DIR
  path = $SHARE_PATH
  browsable = yes
  writable = yes
  public = yes
  guest ok = yes
  guest only = yes
  read only = no
  force user = $TEST_USER
  create mask = 0666
  directory mask = 0777
# END $SHARE_DIR
EOF

    setsebool -P samba_export_all_rw on 2>/dev/null
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-service=samba &>/dev/null
        firewall-cmd --reload &>/dev/null
    fi

    systemctl enable smb nmb &>/dev/null
    
    # KIỂM TRA: Khởi động lại dịch vụ Samba
    systemctl restart smb nmb || { echo "=> [LỖI] Không thể khởi động dịch vụ Samba!"; return 1; }
    
    echo "[OK] Chia sẻ thành công! Truy cập không cần mật khẩu qua: \\\\<IP>\\$SHARE_DIR"
}

# ==========================================================
# MENU CHÍNH
# ==========================================================
while true; do
    echo
    echo "=========================================================="
    echo "    QUẢN LÝ LƯU TRỮ VÀ SHARE DISK (BẢN HOÀN THIỆN)"
    echo "=========================================================="
    echo " 1. Partition (Tạo đĩa cứng & Tự động Mount)"
    echo " 2. Setup LVM (Tạo ổ ảo & Tự động Mount)"
    echo " 3. Setup Samba (Quét ổ đĩa, tạo thư mục con & Chia sẻ)"
    echo " 0. Thoát"
    echo "=========================================================="
    read -r -p "Chọn chức năng (0-3): " c
    case $c in
        1) chay_chuc_nang_partition ;;
        2) setup_lvm ;;
        3) setup_anonymous_samba_quota ;;
        0) echo "Tạm biệt!"; exit 0 ;;
        *) echo "Lựa chọn không hợp lệ." ;;
    esac
done