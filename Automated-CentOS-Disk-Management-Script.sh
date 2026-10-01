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
# 1. NHÓM HÀM PARTITION (Tạo đĩa, Format & Tự động Mount)
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

tao_primary() {
    local FS_TYPE
    echo "--> Tao primary partition 10GB tren $DISK"
    printf "o\nn\np\n1\n\n+10G\nw\n" | fdisk "$DISK"
    partprobe "$DISK"
    sleep 1

    echo "Chọn hệ tập tin (filesystem) để format:"
    echo "  1. ext4 (Khuyến nghị)"
    echo "  2. xfs"
    echo "  3. ext3"
    read -r -p "Chọn định dạng [1]: " fs_choice

    case "$fs_choice" in
        2) FS_TYPE="xfs" ;;
        3) FS_TYPE="ext3" ;;
        *) FS_TYPE="ext4" ;;
    esac

    echo "--> Format $FS_TYPE cho ${DISK}1"
    mkfs -t "$FS_TYPE" "${DISK}1"
}

tao_o_con_lai_cho_lvm() {
    echo "--> Tao extended + logical type 8e tren toan bo o $DISK"
    printf "o\nn\ne\n1\n\n\nn\nl\n\n\nt\n5\n8e\nw\n" | fdisk "$DISK"
    partprobe "$DISK"
    sleep 1
}

chay_chuc_nang_partition() {
    chon_o_dia || return 1
    local MOUNT_DIR="/root/Desktop/DiskLocal"
    
    echo "--- Chọn mục đích sử dụng ổ đĩa $DISK ---"
    echo " A. Lưu trữ tiêu chuẩn: Tạo Primary 10GB, format & TỰ ĐỘNG MOUNT"
    echo " B. Chuẩn bị cho LVM: Tạo phân vùng type 8e"
    read -r -p "Chọn (A/B): " choice

    echo "CẢNH BÁO: Mọi dữ liệu trên $DISK sẽ bị XÓA."
    read -r -p "Tiếp tục? (y/N): " ok
    [ "$ok" != "y" ] && [ "$ok" != "Y" ] && { echo "Đã hủy."; return 0; }

    if [[ "$choice" == "A" || "$choice" == "a" ]]; then
        tao_primary
        mkdir -p "$MOUNT_DIR"
        mount "${DISK}1" "$MOUNT_DIR"
        echo "[OK] Đã gắn kết ${DISK}1 vào $MOUNT_DIR."
        echo "=> Ổ đĩa đã sẵn sàng để sử dụng hoặc chia sẻ qua Chức năng 3."
    elif [[ "$choice" == "B" || "$choice" == "b" ]]; then
        tao_o_con_lai_cho_lvm
        echo "[OK] Phân vùng ${DISK}5 (type 8e) đã sẵn sàng làm nguyên liệu LVM."
    else
        echo "Lựa chọn không hợp lệ."
    fi
}

# ==========================================================
# 2. HÀM LVM (Tạo ổ ảo, Format & Tự động Mount)
# ==========================================================
setup_lvm() {
    local -a DEVICES
    local DEV VG_NAME LV_NAME CONFIRM FS_TYPE
    local MOUNT_DIR="/root/Desktop/DiskLVM"
    
    echo "=== CẤU HÌNH Ổ ĐĨA ẢO LVM ==="
    
    # NÂNG CẤP: Quét và lọc ra các thiết bị khả dụng (Chưa bị mount)
    echo "--> Danh sách các thiết bị/phân vùng KHẢ DỤNG cho LVM (Chưa được mount):"
    echo -e "THIẾT BỊ\tLOẠI\t\tKÍCH THƯỚC"
    
    # Lọc lsblk: Chỉ lấy disk hoặc part, và KHÔNG có Mountpoint
    lsblk -l -o NAME,TYPE,SIZE,MOUNTPOINT | awk '$4 == "" && ($2 == "disk" || $2 == "part") {printf "/dev/%-15s %-15s %s\n", $1, $2, $3}'
    echo "--------------------------------------------------------"
    
    read -r -p "Nhập thiết bị từ bảng trên (cách nhau bằng khoảng trắng, vd: /dev/sdb5 /dev/sdc): " -a DEVICES
    
    # Bẫy lỗi nếu không nhập gì
    [ "${#DEVICES[@]}" -eq 0 ] && { echo "=> LỖI: Chưa nhập thiết bị nào."; return 1; }
    
    # Kiểm tra xem thiết bị có tồn tại và đang bị mount không
    for DEV in "${DEVICES[@]}"; do
        if [ ! -b "$DEV" ]; then
            echo "=> LỖI: Thiết bị $DEV không tồn tại."
            return 1
        fi
        if lsblk -nr -o MOUNTPOINT "$DEV" | grep -q '[^[:space:]]'; then
            echo "=> LỖI: Thiết bị $DEV đang được mount! LVM không thể sử dụng thiết bị này."
            return 1
        fi
    done

    # ... (Phần code cấu hình VG, LV, Format và Mount tiếp theo giữ nguyên như bản trước) ...
    read -r -p "Tên Volume Group [VolumeA]: " VG_NAME
    VG_NAME="${VG_NAME:-VolumeA}"
    read -r -p "Tên Logical Volume [LV]: " LV_NAME
    LV_NAME="${LV_NAME:-LV}"

    read -r -p "Tạo LVM ($VG_NAME/$LV_NAME)? (y/N): " CONFIRM
    [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ] && return 0

    echo "--> Đang khởi tạo LVM..."
    pvcreate "${DEVICES[@]}" || return 1
    vgcreate "$VG_NAME" "${DEVICES[@]}" || return 1
    lvcreate -l 100%FREE -n "$LV_NAME" "$VG_NAME" || return 1

    local LV_TARGET="/dev/$VG_NAME/$LV_NAME"
    
    echo "Chọn hệ tập tin để format:"
    echo "  1. ext4 (Khuyến nghị) | 2. xfs | 3. ext3"
    read -r -p "Chọn định dạng [1]: " fs_choice_lvm
    
    case "$fs_choice_lvm" in
        2) FS_TYPE="xfs" ;;
        3) FS_TYPE="ext3" ;;
        *) FS_TYPE="ext4" ;;
    esac

    echo "--> Định dạng $FS_TYPE cho LVM..."
    mkfs -t "$FS_TYPE" "$LV_TARGET" || return 1
    
    mkdir -p "$MOUNT_DIR"
    mount "$LV_TARGET" "$MOUNT_DIR" || return 1
    
    echo "[OK] Ổ ảo LVM $LV_TARGET đã được mount tại $MOUNT_DIR."
    echo "=> Sẵn sàng sử dụng hoặc dùng Chức năng 3 để cấu hình Samba."
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
    mkdir -p "$SHARE_PATH"
    chmod -R 777 "$SHARE_PATH"
    chcon -Rt samba_share_t "$SHARE_PATH" 2>/dev/null

    # 3. Cập nhật Quota trên ổ đĩa đã mount
    echo "--> Đang áp dụng Quota..."
    yum install -y quota &>/dev/null
    id "$TEST_USER" &>/dev/null || useradd "$TEST_USER"

    sed -i "\|[[:space:]]$MOUNT_DIR[[:space:]]|d" /etc/fstab
    echo "$TARGET_DEV $MOUNT_DIR $CURRENT_FS defaults,usrquota,grpquota 0 0" >> /etc/fstab
    mount -o remount,usrquota,grpquota "$MOUNT_DIR"

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
    systemctl restart smb nmb
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