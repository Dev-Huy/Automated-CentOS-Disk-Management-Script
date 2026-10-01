#!/bin/bash
# ==============================================================================
# SCRIPT QUẢN LÝ LƯU TRỮ VÀ SHARE DISK (BẢN HOÀN THIỆN - AGILE & DECOUPLED)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    echo "Hãy chạy script bằng quyền root (sudo ./quan_ly_centos_samba.sh)"
    exit 1
fi

TARGET_USER=""
TARGET_DISK=""

# ==========================================================
# MODULE 1: CORE & UI (Giao diện & Tiện ích cốt lõi)
# Chuyển hướng log ra >&2 để bảo vệ luồng dữ liệu biến toàn cục
# ==========================================================
msg_info() { echo -e "\n--> $1" >&2; }
msg_ok()   { echo -e "[OK] $1" >&2; }
msg_err()  { echo -e "=> [LỖI] $1" >&2; }
msg_warn() { echo -e "=> [CẢNH BÁO] $1" >&2; }

get_fs_and_force_flag() {
    case "$1" in
        2) echo "xfs -f" ;;
        3) echo "ext3 -F" ;;
        *) echo "ext4 -F" ;;
    esac
}

format_and_mount() {
    local dev=$1 fs_type=$2 force_flag=$3 mount_dir=$4
    msg_info "Format $fs_type cho $dev..."
    mkfs -t "$fs_type" $force_flag "$dev" || { msg_err "Format thất bại!"; return 1; }
    
    mkdir -p "$mount_dir" || { msg_err "Lỗi tạo thư mục $mount_dir"; return 1; }
    mount "$dev" "$mount_dir" || { msg_err "Lỗi mount $dev"; return 1; }
    msg_ok "Đã gắn kết $dev vào $mount_dir"
}

# ==========================================================
# MODULE 2: RAW DISK CALCULATOR (Dành riêng cho Partition & LVM)
# Đã khắc phục triệt để lỗi ẩn ổ đĩa mới/chưa khởi tạo nhờ Fail-safe
# ==========================================================
is_os_disk() { 
    lsblk -nr -o MOUNTPOINT "$1" 2>/dev/null | grep -qE '^/$|^/boot' 
}

get_part_count() { 
    local count=$(lsblk -nr -o TYPE "$1" 2>/dev/null | grep -c "part")
    echo "${count:-0}"
}

get_free_mb() {
    local dev=$1
    # Lấy tổng dung lượng (Byte), dùng grep lọc sạch chữ cái
    local tot=$(lsblk -dnr -b -o SIZE "$dev" 2>/dev/null | grep -Eo '[0-9]+' | head -n 1)
    tot=${tot:-0}

    # Lấy dung lượng đã dùng, bỏ qua extended partition để tránh cộng đúp
    local usd=$(lsblk -nr -b -o SIZE,TYPE,FSTYPE "$dev" 2>/dev/null | awk '$2=="part" && $3!="extended" {sum+=$1} END {print sum+0}')
    usd=${usd:-0}

    local free_bytes=$((tot - usd))
    [ "$free_bytes" -lt 0 ] && free_bytes=0

    echo $((free_bytes / 1024 / 1024))
}

chon_o_dia() {
    msg_info "DANH SÁCH Ổ ĐĨA KHẢ DỤNG (Cho Partition & LVM)"
    local disks=$(lsblk -nd -o NAME,TYPE | awk '$2=="disk" && $1!="sr0" && !/loop/ {print $1}')
    local has_disk=0
    
    for d in $disks; do
        local dev="/dev/$d"
        is_os_disk "$dev" && continue
        
        local p_count=$(get_part_count "$dev")
        local free_mb=$(get_free_mb "$dev")
        
        [ "$p_count" -ge 4 ] && continue
        [ -n "$free_mb" ] && [ "$free_mb" -lt 10 ] && continue
        
        has_disk=1
        echo "-----------------------------------------------------------------" >&2
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$dev" >&2
        echo "=> Ổ $d: Đang có $p_count/4 phân vùng | Trống ước tính: ~${free_mb} MB" >&2
    done
    echo "-----------------------------------------------------------------" >&2

    [ $has_disk -eq 0 ] && { msg_err "Không có ổ đĩa vật lý nào khả dụng."; return 1; }
    
    read -r -p "Nhập tên ổ đĩa muốn thao tác (vd: sdb): " name
    local target="/dev/$name"
    
    if [ ! -b "$target" ] || is_os_disk "$target"; then
        msg_err "Ổ đĩa không hợp lệ hoặc chứa hệ điều hành."
        return 1
    fi
    
    TARGET_DISK="$target"
    return 0
}

# ==========================================================
# MODULE 3: PARTITION MANAGEMENT (Nghiệp vụ Phân vùng)
# ==========================================================
chay_chuc_nang_partition() {
    chon_o_dia || return 1
    local disk="$TARGET_DISK"

    msg_info "CHẾ ĐỘ AN TOÀN: Giữ nguyên dữ liệu cũ, chỉ tạo thêm phân vùng."
    read -r -p "Tiếp tục? (y/N): " ok
    [[ "$ok" != [yY]* ]] && return 0

    read -r -p "Nhập dung lượng (vd: +1G, +500M) hoặc Enter để dùng toàn bộ: " part_size
    
    # Auto-Sanitize đầu vào
    if [ -n "$part_size" ]; then
        part_size=$(echo "$part_size" | tr -d ' ' | sed 's/[bB]$//' | tr '[:lower:]' '[:upper:]')
        [[ ! "$part_size" =~ ^[+-] ]] && part_size="+$part_size"
    fi

    echo "1. ext4 (Khuyến nghị) | 2. xfs | 3. ext3"
    read -r -p "Chọn định dạng [1-3]: " fs_choice

    local old_parts=$(lsblk -nr -o NAME "$disk")
    msg_info "Đang tiến hành cắt đĩa $disk..."
    
    if [ -z "$part_size" ]; then
        printf "n\np\n\n\n\nw\n" | fdisk "$disk" >/dev/null 2>&1
    else
        printf "n\np\n\n\n%s\nw\n" "${part_size}" | fdisk "$disk" >/dev/null 2>&1
    fi
    partprobe "$disk" 2>/dev/null; sleep 2

    local new_part=""
    for p in $(lsblk -nr -o NAME "$disk"); do
        ! echo "$old_parts" | grep -q "^$p$" && new_part="/dev/$p" && break
    done

    [ -z "$new_part" ] && { msg_err "Lỗi cắt đĩa (Sai cú pháp hoặc không đủ không gian)."; return 1; }
    msg_ok "Đã tạo phân vùng thành công: $new_part"

    read -r -p "Force Format (Xóa sạch tàn dư hệ tập tin cũ)? (y/N): " force_cfm
    local fs_cfg=($(get_fs_and_force_flag "$fs_choice"))
    local force_flag=""
    [[ "$force_cfm" == [yY]* ]] && force_flag="${fs_cfg[1]}"

    format_and_mount "$new_part" "${fs_cfg[0]}" "$force_flag" "/root/Desktop/DiskLocal_$(basename "$new_part")"
}

# ==========================================================
# MODULE 4: LVM MANAGEMENT (Nghiệp vụ Ổ đĩa ảo)
# ==========================================================
prepare_lvm_disk() {
    local dev=$1
    if [ -b "$dev" ] && ! is_os_disk "$dev"; then
        msg_info "Đang ép mã 8e cho $dev..." >&2
        printf "o\nn\np\n1\n\n\nt\n8e\nw\n" | fdisk "$dev" >/dev/null 2>&1
        partprobe "$dev" 2>/dev/null; sleep 1
        [ -b "${dev}1" ] && echo "${dev}1"
    fi
}

setup_lvm() {
    echo -e "\n=== QUẢN LÝ Ổ ĐĨA ẢO LVM ==="
    echo " 1. Khởi tạo LVM mới (Gộp ổ đĩa trống)"
    echo " 2. Mở rộng LVM an toàn (Giữ nguyên dữ liệu)"
    read -r -p "Chọn chức năng [1-2]: " mode

    if [ "$mode" == "1" ]; then
        msg_info "KHỞI TẠO LVM MỚI"
        local disks_avail=$(lsblk -nd -o NAME,TYPE | awk '$2=="disk" && $1!="sr0" && !/loop/ {print $1}')
        for d in $disks_avail; do
            ! is_os_disk "/dev/$d" && echo "  - $d ($(lsblk -dn -o SIZE "/dev/$d"))"
        done
        
        read -r -p "Nhập tên các ổ gốc để gộp (vd: sdb sdc): " -a disks
        [ ${#disks[@]} -eq 0 ] && return 1

        local lvm_parts=()
        for d in "${disks[@]}"; do
            local p=$(prepare_lvm_disk "/dev/${d#/dev/}")
            [ -n "$p" ] && lvm_parts+=("$p")
        done

        [ ${#lvm_parts[@]} -eq 0 ] && return 1

        read -r -p "Tên VG [VolumeA]: " vg; vg="${vg:-VolumeA}"
        read -r -p "Tên LV [LV]: " lv; lv="${lv:-LV}"

        pvcreate "${lvm_parts[@]}" && vgcreate "$vg" "${lvm_parts[@]}" && lvcreate -l 100%FREE -n "$lv" "$vg" || return 1

        echo "1. ext4 | 2. xfs | 3. ext3"
        read -r -p "Định dạng cho LVM [1-3]: " fs_choice
        local fs_cfg=($(get_fs_and_force_flag "$fs_choice"))

        format_and_mount "/dev/$vg/$lv" "${fs_cfg[0]}" "${fs_cfg[1]}" "/root/Desktop/DiskLVM_${vg}_${lv}"

    elif [ "$mode" == "2" ]; then
        msg_info "MỞ RỘNG LVM AN TOÀN"
        vgs 2>/dev/null || return 1
        read -r -p "Nhập tên VG muốn mở rộng: " t_vg
        read -r -p "Nhập tên LV muốn mở rộng: " t_lv
        local lv_path="/dev/$t_vg/$t_lv"
        [ ! -b "$lv_path" ] && return 1

        read -r -p "Nhập các ổ đĩa MỚI bổ sung (vd: sdc sdd): " -a disks
        local new_parts=()
        for d in "${disks[@]}"; do
            local p=$(prepare_lvm_disk "/dev/${d#/dev/}")
            [ -n "$p" ] && new_parts+=("$p")
        done
        [ ${#new_parts[@]} -eq 0 ] && return 1

        pvcreate "${new_parts[@]}" && vgextend "$t_vg" "${new_parts[@]}" && lvextend -l +100%FREE "$lv_path" || return 1

        local cur_fs=$(blkid -s TYPE -o value "$lv_path")
        if [ "$cur_fs" == "xfs" ]; then
            local mnt=$(findmnt -no TARGET "$lv_path")
            if [ -n "$mnt" ]; then xfs_growfs "$mnt"; else
                mkdir -p /mnt/tmp_resize && mount "$lv_path" /mnt/tmp_resize
                xfs_growfs /mnt/tmp_resize && umount /mnt/tmp_resize && rm -rf /mnt/tmp_resize
            fi
        else
            resize2fs "$lv_path"
        fi
        msg_ok "Mở rộng thành công: $lv_path"
    fi
}

# ==========================================================
# MODULE 5: USER & QUOTA MANAGEMENT (Độc lập, làm việc với Mount Point)
# ==========================================================
chon_user_he_thong() {
    local user_list=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd)
    echo -e "\n[Danh sách User] \n  - nobody (Ẩn danh)"
    [ -n "$user_list" ] && echo "$user_list" | column | sed 's/^/  /'
    
    read -r -p "Nhập tên User muốn áp dụng (vd: nobody): " selected_user
    if ! id "$selected_user" &>/dev/null; then
        msg_err "Tài khoản KHÔNG TỒN TẠI. Từ chối thực thi."
        return 1
    fi
    TARGET_USER="$selected_user"
    return 0
}

cauhinh_quota() {
    msg_info "CẤU HÌNH QUOTA (HẠN NGẠCH)"
    df -hT | grep -E 'ext3|ext4|xfs' | awk '{printf "%-20s %-15s %s\n", $1, $2, $7}'
    
    read -r -p "Nhập thư mục gốc (MOUNT POINT) cần áp Quota: " mnt_dir
    mountpoint -q "$mnt_dir" || { msg_err "Chưa mount."; return 1; }

    local dev=$(df "$mnt_dir" | tail -1 | awk '{print $1}')
    local fs=$(df -T "$mnt_dir" | tail -1 | awk '{print $2}')
    [ "$fs" == "xfs" ] && { msg_warn "Hệ XFS cần dùng xfs_quota."; return 1; }

    chon_user_he_thong || return 1

    yum install -y quota &>/dev/null
    sed -i "\|[[:space:]]$mnt_dir[[:space:]]|d" /etc/fstab
    echo "$dev $mnt_dir $fs defaults,usrquota,grpquota 0 0" >> /etc/fstab
    mount -o remount,usrquota,grpquota "$mnt_dir" 2>/dev/null
    quotacheck -cugm "$mnt_dir" 2>/dev/null; quotaon -v "$mnt_dir" 2>/dev/null

    read -r -p "Soft Limit MB (Enter = 0): " block_soft_mb
    read -r -p "Hard Limit MB (Enter = 0): " block_hard_mb
    read -r -p "Soft Limit Inodes (Enter = 0): " inode_soft
    read -r -p "Hard Limit Inodes (Enter = 0): " inode_hard

    # Auto-sanitize Quota inputs
    block_soft_mb=$(echo "$block_soft_mb" | tr -cd '0-9')
    block_hard_mb=$(echo "$block_hard_mb" | tr -cd '0-9')
    inode_soft=$(echo "$inode_soft" | tr -cd '0-9')
    inode_hard=$(echo "$inode_hard" | tr -cd '0-9')

    local b_soft=$(( ${block_soft_mb:-0} * 1024 ))
    local b_hard=$(( ${block_hard_mb:-0} * 1024 ))
    
    setquota -u "$TARGET_USER" "$b_soft" "$b_hard" "${inode_soft:-0}" "${inode_hard:-0}" "$mnt_dir" 2>/dev/null

    read -r -p "Bật Grace Period 7 ngày? (y/N): " set_grace
    [[ "$set_grace" == [yY]* ]] && setquota -t 604800 604800 "$mnt_dir" 2>/dev/null

    msg_ok "Thành công. Trạng thái Quota của $TARGET_USER:"
    repquota -as | grep -E "User|$TARGET_USER"
}

# ==========================================================
# MODULE 6: SAMBA SHARE (Độc lập, làm việc với Mount Point)
# ==========================================================
cauhinh_samba() {
    msg_info "CẤU HÌNH SAMBA SERVER"
    df -hT | grep -E 'ext3|ext4|xfs' | awk '{printf "%-20s %-15s %s\n", $1, $2, $7}'
    
    read -r -p "Nhập thư mục gốc (MOUNT POINT) cần Share: " mnt_dir
    mountpoint -q "$mnt_dir" || { msg_err "Chưa mount."; return 1; }

    msg_info "THƯ MỤC CÓ SẴN:"
    find "$mnt_dir" -maxdepth 1 -mindepth 1 -type d ! -name "lost+found" -exec basename {} \; | sed 's/^/  - /'

    read -r -p "Nhập tên Thư mục (Chọn từ trên hoặc Tạo mới): " share_dir
    [ -z "$share_dir" ] && return 1
    
    local share_path="$mnt_dir/$share_dir"
    [ ! -d "$share_path" ] && mkdir -p "$share_path"

    msg_info "CHỌN TÀI KHOẢN ĐẠI DIỆN"
    chon_user_he_thong || return 1

    chmod -R 777 "$share_path" && chcon -Rt samba_share_t "$share_path" 2>/dev/null
    chown -R "$TARGET_USER" "$share_path"

    yum install -y samba samba-client samba-common &>/dev/null
    chmod o+x /root /root/Desktop "$mnt_dir" 2>/dev/null
    
    local smb_conf="/etc/samba/smb.conf"
    cp -n "$smb_conf" "${smb_conf}.bak"
    grep -q "map to guest" "$smb_conf" || sed -i '/^\[global\]/a\        map to guest = Bad User\n        security = user' "$smb_conf"
    sed -i "/^\[$share_dir\]/,/^# END $share_dir/d" "$smb_conf"
    
    cat >> "$smb_conf" <<EOF
[$share_dir]
# BEGIN $share_dir
  path = $share_path
  browsable = yes
  writable = yes
  guest ok = yes
  force user = $TARGET_USER
  create mask = 0666
  directory mask = 0777
# END $share_dir
EOF

    setsebool -P samba_export_all_rw on 2>/dev/null
    systemctl enable smb nmb &>/dev/null
    systemctl restart smb nmb || return 1
    msg_ok "CHIA SẺ THÀNH CÔNG: \\\\<IP>\\$share_dir"
}

# ==========================================================
# MODULE 7: ROUTER (Menu điều hướng chính)
# ==========================================================
while true; do
    echo -e "\n=========================================================="
    echo "    HỆ THỐNG QUẢN LÝ LƯU TRỮ TRUNG TÂM (CENTOS)"
    echo "=========================================================="
    echo " 1. Phân vùng đĩa cứng (Partition an toàn)"
    echo " 2. Quản lý Ổ đĩa ảo (LVM)"
    echo " 3. Quản trị Hạn ngạch (Quota)"
    echo " 4. Chia sẻ mạng (Samba)"
    echo " 0. Thoát"
    read -r -p "Chọn chức năng [0-4]: " c
    case $c in
        1) chay_chuc_nang_partition ;;
        2) setup_lvm ;;
        3) cauhinh_quota ;;
        4) cauhinh_samba ;;
        0) exit 0 ;;
        *) msg_warn "Lựa chọn không hợp lệ." ;;
    esac
done
