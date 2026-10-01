#!/bin/bash
# ==============================================================================
# SCRIPT QUẢN LÝ LƯU TRỮ VÀ SHARE DISK (BẢN HOÀN THIỆN - AGILE & DECOUPLED)
# Kiến trúc: Feature-Sliced Design (Độc lập module, Đơn nhiệm, An toàn dữ liệu)
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
    echo "Hãy chạy script bằng quyền root (sudo ./quan_ly_centos_samba.sh)"
    exit 1
fi

TARGET_USER=""

# ==========================================================
# MODULE 1: CORE & UI (Giao diện & Tiện ích cốt lõi)
# ==========================================================
msg_info() { echo -e "\n--> $1"; }
msg_ok()   { echo -e "[OK] $1"; }
msg_err()  { echo -e "=> [LỖI] $1"; }
msg_warn() { echo -e "=> [CẢNH BÁO] $1"; }

# ==========================================================
# MODULE 2: DISK & PARTITION (Phân vùng an toàn & Tự động)
# ==========================================================
is_os_disk() { lsblk -nr -o MOUNTPOINT "$1" | grep -qE '^/$|^/boot'; }
get_part_count() { lsblk -nr -o TYPE "$1" | grep -c "part"; }
get_free_mb() {
    local tot=$(lsblk -dnr -b -o SIZE "$1")
    local usd=$(lsblk -nr -b -o SIZE,TYPE "$1" | awk '$2=="part" {sum+=$1} END {print sum+0}')
    echo $(((tot - usd) / 1024 / 1024))
}

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

chon_o_dia() {
    msg_info "DANH SÁCH Ổ ĐĨA KHẢ DỤNG (Đã ẩn đĩa OS, đĩa đầy hoặc max 4 phân vùng)"
    local disks=$(lsblk -nd -o NAME,TYPE | awk '$2=="disk" && $1!="sr0" && !/loop/ {print $1}')
    local has_disk=0
    
    for d in $disks; do
        local dev="/dev/$d"
        is_os_disk "$dev" && continue
        [ "$(get_part_count "$dev")" -ge 4 ] && continue
        
        local free_mb=$(get_free_mb "$dev")
        [ "$free_mb" -lt 10 ] && continue
        
        has_disk=1
        echo "-----------------------------------------------------------------"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$dev"
        echo "=> Ổ $d: $(get_part_count "$dev")/4 phân vùng | Trống ước tính: ~${free_mb} MB"
    done
    echo "-----------------------------------------------------------------"

    [ $has_disk -eq 0 ] && { msg_err "Không có ổ đĩa nào khả dụng."; return 1; }
    
    read -r -p "Nhập tên ổ đĩa muốn thao tác (vd: sdb): " name
    local target="/dev/$name"
    
    if [ ! -b "$target" ] || is_os_disk "$target" || [ "$(get_part_count "$target")" -ge 4 ] || [ "$(get_free_mb "$target")" -lt 10 ]; then
        msg_err "Ổ đĩa không hợp lệ, đầy dung lượng hoặc bị từ chối truy cập."
        return 1
    fi
    echo "$target"
}

chay_chuc_nang_partition() {
    local disk=$(chon_o_dia)
    [ -z "$disk" ] && return 1

    msg_info "CHẾ ĐỘ AN TOÀN: Giữ nguyên dữ liệu cũ, chỉ tạo thêm phân vùng trên không gian trống."
    read -r -p "Tiếp tục? (y/N): " ok
    [[ "$ok" != [yY]* ]] && return 0

    read -r -p "Nhập dung lượng (vd: +10G) hoặc Enter để dùng toàn bộ: " part_size
    echo "1. ext4 (Khuyến nghị) | 2. xfs | 3. ext3"
    read -r -p "Chọn định dạng [1-3]: " fs_choice

    local old_parts=$(lsblk -nr -o NAME "$disk")
    msg_info "Đang phân vùng mới trên $disk..."
    
    # Bỏ lệnh 'o', dùng 'n' để giữ nguyên Partition Table hiện tại
    if [ -z "$part_size" ]; then
        printf "n\np\n\n\n\nw\n" | fdisk "$disk" >/dev/null 2>&1
    else
        printf "n\np\n\n\n%s\nw\n" "${part_size}" | fdisk "$disk" >/dev/null 2>&1
    fi
    partprobe "$disk" 2>/dev/null; sleep 2

    # Tìm phân vùng vừa mới sinh ra
    local new_part=""
    for p in $(lsblk -nr -o NAME "$disk"); do
        ! echo "$old_parts" | grep -q "^$p$" && new_part="/dev/$p" && break
    done

    [ -z "$new_part" ] && { msg_err "Lỗi tạo phân vùng (hết dung lượng trống)."; return 1; }
    msg_ok "Đã tạo thành công: $new_part"

    read -r -p "Bạn có muốn ép buộc định dạng (Force Format - xóa sạch tàn dư hệ tập tin cũ)? (y/N): " force_cfm
    local fs_cfg=($(get_fs_and_force_flag "$fs_choice"))
    local force_flag=""
    [[ "$force_cfm" == [yY]* ]] && force_flag="${fs_cfg[1]}"

    # Mount động theo tên phân vùng
    format_and_mount "$new_part" "${fs_cfg[0]}" "$force_flag" "/root/Desktop/DiskLocal_$(basename "$new_part")"
}

# ==========================================================
# MODULE 3: LVM (Logical Volume Manager - New & Extend)
# ==========================================================
prepare_lvm_disk() {
    local dev=$1
    local free_start free_end free_size
    local new_part part_num

    # Chỉ làm việc với block device thật và tuyệt đối không đụng vào OS disk.
    if [ ! -b "$dev" ] || is_os_disk "$dev"; then
        return 1
    fi

    # Dùng parted để tìm vùng UNALLOCATED (Free Space).
    # Tuyệt đối không dùng "fdisk o" vì lệnh này sẽ xóa toàn bộ partition table.
    command -v parted >/dev/null 2>&1 || {
        msg_err "Thiếu lệnh 'parted'. Hãy cài: yum install -y parted"
        return 1
    }

    msg_info "Đang quét vùng trống chưa phân vùng trên $dev..."

    # Lấy vùng Free Space đầu tiên có kích thước >= 10 MiB.
    # Output: START|END|SIZE|Free Space
    while IFS='|' read -r free_start free_end free_size free_type; do
        [ "$free_type" = "Free Space" ] || continue

        free_start="${free_start//[[:space:]]/}"
        free_end="${free_end//[[:space:]]/}"
        free_size="${free_size//[[:space:]]/}"

        if awk "BEGIN {exit !($free_size >= 10)}"; then
            break
        fi

        free_start=""
        free_end=""
    done < <(
        parted -m -s "$dev" unit MiB print free 2>/dev/null |
        awk -F: '$5 ~ /Free Space/ {gsub(/MiB/, "", $2); gsub(/MiB/, "", $3); gsub(/MiB/, "", $4); print $2 "|" $3 "|" $4 "|" $5}'
    )

    if [ -z "$free_start" ] || [ -z "$free_end" ]; then
        msg_warn "Không tìm thấy vùng trống chưa phân vùng >= 10 MiB trên $dev."
        return 1
    fi

    msg_ok "Tìm thấy vùng trống khả dụng trên $dev: ${free_start}MiB -> ${free_end}MiB (~${free_size}MiB)"

    # Xác định số partition tiếp theo mà không ảnh hưởng các partition hiện có.
    part_num=$(lsblk -nr -o PARTN "$dev" 2>/dev/null | sort -n | tail -1)
    part_num=$(( ${part_num:-0} + 1 ))

    msg_info "Tạo partition LVM mới trong vùng trống: ${free_start}MiB -> ${free_end}MiB"

    # Chỉ tạo partition trong Free Space, không xóa partition cũ.
    parted -s -a optimal "$dev" unit MiB mkpart primary "$free_start" "$free_end" || {
        msg_err "Không thể tạo partition LVM trên vùng trống của $dev."
        return 1
    }

    partprobe "$dev" 2>/dev/null
    udevadm settle 2>/dev/null
    sleep 1

    # Tìm partition vừa tạo theo PARTN, hỗ trợ cả /dev/sdX và /dev/nvmeXnY.
    new_part=$(lsblk -nr -o NAME,PARTN "$dev" 2>/dev/null |
        awk -v n="$part_num" '$2 == n {print "/dev/" $1; exit}')

    if [ -z "$new_part" ] || [ ! -b "$new_part" ]; then
        new_part=$(lsblk -nr -o NAME,TYPE "$dev" 2>/dev/null |
            awk '$2 == "part" {last=$1} END {if (last != "") print "/dev/" last}')
    fi

    [ -b "$new_part" ] || {
        msg_err "Không xác định được partition LVM vừa tạo trên $dev."
        return 1
    }

    # Đánh dấu partition là LVM.
    parted -s "$dev" set "$part_num" lvm on 2>/dev/null || true

    partprobe "$dev" 2>/dev/null
    udevadm settle 2>/dev/null
    sleep 1

    msg_ok "Đã tạo partition LVM an toàn: $new_part"
    echo "$new_part"
}

setup_lvm() {
    echo -e "\n=== QUẢN LÝ Ổ ĐĨA ẢO LVM ==="
    echo " 1. Khởi tạo LVM mới (Gộp ổ đĩa trống thành 1 LVM)"
    echo " 2. Mở rộng LVM an toàn (Giữ nguyên dữ liệu hiện tại)"
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

        [ ${#lvm_parts[@]} -eq 0 ] && { msg_err "Không có phân vùng hợp lệ."; return 1; }

        read -r -p "Tên VG [VolumeA]: " vg; vg="${vg:-VolumeA}"
        read -r -p "Tên LV [LV]: " lv; lv="${lv:-LV}"

        msg_info "Đang khởi tạo cấu trúc LVM..."
        pvcreate "${lvm_parts[@]}" && vgcreate "$vg" "${lvm_parts[@]}" && lvcreate -l 100%FREE -n "$lv" "$vg" || return 1

        echo "1. ext4 | 2. xfs | 3. ext3"
        read -r -p "Định dạng cho LVM [1-3]: " fs_choice
        local fs_cfg=($(get_fs_and_force_flag "$fs_choice"))

        format_and_mount "/dev/$vg/$lv" "${fs_cfg[0]}" "${fs_cfg[1]}" "/root/Desktop/DiskLVM_${vg}_${lv}"

    elif [ "$mode" == "2" ]; then
        msg_info "MỞ RỘNG LVM AN TOÀN"
        vgs 2>/dev/null || { msg_err "Không tìm thấy Volume Group nào."; return 1; }
        
        read -r -p "Nhập tên VG muốn mở rộng: " t_vg
        lvs "$t_vg" 2>/dev/null && read -r -p "Nhập tên LV muốn mở rộng: " t_lv
        local lv_path="/dev/$t_vg/$t_lv"
        [ ! -b "$lv_path" ] && { msg_err "LV $lv_path không tồn tại."; return 1; }

        read -r -p "Nhập các ổ đĩa MỚI muốn thêm vào LVM (vd: sdc sdd): " -a disks
        local new_parts=()
        for d in "${disks[@]}"; do
            local p=$(prepare_lvm_disk "/dev/${d#/dev/}")
            [ -n "$p" ] && new_parts+=("$p")
        done

        [ ${#new_parts[@]} -eq 0 ] && return 1

        msg_info "Đang bổ sung dung lượng..."
        pvcreate "${new_parts[@]}" && vgextend "$t_vg" "${new_parts[@]}" && lvextend -l +100%FREE "$lv_path" || return 1

        msg_info "Đang ép giãn hệ tập tin (Resize FS)..."
        local cur_fs=$(blkid -s TYPE -o value "$lv_path")
        if [ "$cur_fs" == "xfs" ]; then
            local mnt=$(findmnt -no TARGET "$lv_path")
            if [ -n "$mnt" ]; then 
                xfs_growfs "$mnt"
            else
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
# MODULE 4: USER & QUOTA (Quản trị Người dùng & Hạn ngạch)
# ==========================================================
chon_user_he_thong() {
    msg_info "LỰA CHỌN TÀI KHOẢN ĐÍCH"
    local user_list=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd)
    
    echo "-----------------------------------------------------------------"
    echo "[Tài khoản Ẩn danh / Anonymous mặc định]"
    echo "  - nobody (Dùng cho khách vãng lai, truy cập tự do)"
    echo -e "\n[Các tài khoản định danh hiện có (UID >= 1000)]"
    [ -z "$user_list" ] && echo "  (Hệ thống chưa có user thông thường nào)" || echo "$user_list" | column | sed 's/^/  /'
    echo "-----------------------------------------------------------------"

    read -r -p "Nhập tên người dùng từ danh sách trên (vd: nobody): " selected_user
    
    if ! id "$selected_user" &>/dev/null; then
        msg_err "Tài khoản '$selected_user' KHÔNG TỒN TẠI!"
        msg_warn "Chính sách hệ thống: Không tự sinh user rác. Vui lòng chọn user có sẵn."
        return 1
    fi

    TARGET_USER="$selected_user"
    msg_ok "Đã chốt tài khoản: $TARGET_USER"
    return 0
}

cauhinh_quota() {
    msg_info "CẤU HÌNH HẠN NGẠCH LƯU TRỮ (QUOTA NÂNG CAO)"
    df -hT | grep -E 'ext3|ext4|xfs' | awk '{printf "%-20s %-15s %s\n", $1, $2, $7}'
    
    read -r -p "Nhập thư mục gốc (MOUNT POINT) cần áp dụng Quota: " mnt_dir
    mountpoint -q "$mnt_dir" || { msg_err "Thư mục chưa được mount."; return 1; }

    local dev=$(df "$mnt_dir" | tail -1 | awk '{print $1}')
    local fs=$(df -T "$mnt_dir" | tail -1 | awk '{print $2}')

    [ "$fs" == "xfs" ] && { msg_warn "Hệ XFS cần dùng xfs_quota thủ công."; return 1; }

    chon_user_he_thong || return 1

    msg_info "Đang kích hoạt môi trường Quota..."
    yum install -y quota &>/dev/null
    
    sed -i "\|[[:space:]]$mnt_dir[[:space:]]|d" /etc/fstab
    echo "$dev $mnt_dir $fs defaults,usrquota,grpquota 0 0" >> /etc/fstab
    mount -o remount,usrquota,grpquota "$mnt_dir" 2>/dev/null
    
    quotacheck -cugm "$mnt_dir" 2>/dev/null
    quotaon -v "$mnt_dir" 2>/dev/null

    echo -e "\n--- THIẾT LẬP DUNG LƯỢNG (MB) ---"
    read -r -p "Soft Limit (Cảnh báo) [Enter = Vô hạn]: " block_soft_mb
    read -r -p "Hard Limit (Chặn cứng) [Enter = Vô hạn]: " block_hard_mb
    
    echo -e "\n--- THIẾT LẬP SỐ LƯỢNG FILE (INODES) ---"
    read -r -p "Soft Limit Inodes [Enter = Vô hạn]: " inode_soft
    read -r -p "Hard Limit Inodes [Enter = Vô hạn]: " inode_hard

    local b_soft=$(( ${block_soft_mb:-0} * 1024 ))
    local b_hard=$(( ${block_hard_mb:-0} * 1024 ))
    local i_soft=${inode_soft:-0}
    local i_hard=${inode_hard:-0}

    msg_info "Đang áp dụng Hạn ngạch cho '$TARGET_USER'..."
    setquota -u "$TARGET_USER" "$b_soft" "$b_hard" "$i_soft" "$i_hard" "$mnt_dir" 2>/dev/null

    read -r -p "Bật thời gian ân hạn 7 ngày cho cảnh báo Soft Limit? (y/N): " set_grace
    if [[ "$set_grace" == [yY]* ]]; then
        setquota -t 604800 604800 "$mnt_dir" 2>/dev/null
        msg_ok "Đã cấu hình Grace Period (7 ngày)."
    fi

    msg_ok "BÁO CÁO QUOTA HIỆN TẠI:"
    repquota -as | grep -E "User|$TARGET_USER"
}

# ==========================================================
# MODULE 5: FILE SERVER (Samba Share thông minh)
# ==========================================================
cauhinh_samba() {
    msg_info "CẤU HÌNH CHIA SẺ MẠNG (SAMBA SERVER)"
    df -hT | grep -E 'ext3|ext4|xfs' | awk '{printf "%-20s %-15s %s\n", $1, $2, $7}'
    
    read -r -p "Nhập thư mục gốc (MOUNT POINT) chứa thư mục chia sẻ: " mnt_dir
    mountpoint -q "$mnt_dir" || { msg_err "Thư mục chưa được mount."; return 1; }

    msg_info "QUÉT THƯ MỤC CÓ SẴN TRONG $mnt_dir"
    local existing_dirs=$(find "$mnt_dir" -maxdepth 1 -mindepth 1 -type d ! -name "lost+found" -exec basename {} \;)
    
    echo "-----------------------------------------------------------------"
    [ -z "$existing_dirs" ] && echo "  (Chưa có thư mục con nào)" || echo "$existing_dirs" | column | sed 's/^/  - /'
    echo "-----------------------------------------------------------------"

    read -r -p "Nhập tên thư mục muốn Share (Chọn ở trên hoặc gõ tên Mới): " share_dir
    [ -z "$share_dir" ] && return 1
    
    local share_path="$mnt_dir/$share_dir"

    if [ -d "$share_path" ]; then
        msg_ok "Sử dụng thư mục hiện có: $share_path"
    else
        msg_info "Tạo mới thư mục: $share_path"
        mkdir -p "$share_path" || return 1
    fi

    msg_info "THIẾT LẬP TÀI KHOẢN ĐẠI DIỆN"
    chon_user_he_thong || return 1

    msg_info "Cấp quyền sở hữu ($TARGET_USER) và SELinux..."
    chmod -R 777 "$share_path" && chcon -Rt samba_share_t "$share_path" 2>/dev/null
    chown -R "$TARGET_USER" "$share_path"

    msg_info "Cấu hình dịch vụ Samba..."
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
    systemctl restart smb nmb || { msg_err "Lỗi Restart Samba"; return 1; }
    
    msg_ok "CHIA SẺ THÀNH CÔNG! Truy cập từ Windows/LAN qua: \\\\<IP>\\$share_dir"
}

# ==========================================================
# MODULE 6: ROUTER (Menu điều hướng chính)
# ==========================================================
while true; do
    echo -e "\n=========================================================="
    echo "    HỆ THỐNG QUẢN LÝ LƯU TRỮ TRUNG TÂM (CENTOS)"
    echo "=========================================================="
    echo " 1. Phân vùng đĩa cứng (Partition an toàn & Mount)"
    echo " 2. Quản lý Ổ đĩa ảo (Khởi tạo mới hoặc Mở rộng LVM)"
    echo " 3. Quản trị Hạn ngạch (Quota Blocks & Inodes)"
    echo " 4. Chia sẻ mạng thư mục"
    echo " 0. Thoát hệ thống"
    read -r -p "Chọn chức năng [0-4]: " c
    case $c in
        1) chay_chuc_nang_partition ;;
        2) setup_lvm ;;
        3) cauhinh_quota ;;
        4) cauhinh_samba ;;
        0) msg_ok "Hệ thống thoát an toàn. Tạm biệt!"; exit 0 ;;
        *) msg_warn "Lựa chọn không hợp lệ." ;;
    esac
done
