#!/usr/bin/env bash
set -euo pipefail

# ===== 配置项：可以通过环境变量覆盖 =====
TARGET_DATASETS_CACHE="${TARGET_DATASETS_CACHE:-/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/datasets}"
GROUP="${GROUP:-hf-users}"
DRY_RUN="${DRY_RUN:-0}"
COPY_BACKEND="${COPY_BACKEND:-rsync}"
FPSYNC_JOBS="${FPSYNC_JOBS:-8}"
COPY_LINKS="${COPY_LINKS:-auto}"

usage() {
  echo "Usage:"
  echo "  sudo DRY_RUN=1 ${0} /data"
  echo "  sudo ${0} /home"
  echo "  sudo COPY_BACKEND=fpsync FPSYNC_JOBS=8 ${0} /data"
  echo "  sudo COPY_LINKS=yes ${0} /data"
  echo
  echo "Please specify exactly one scan root directory, for example: /data or /home"
}

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

run() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

copy_datasets_cache() {
  local source_datasets_cache="${1}"
  local target_datasets_cache="${2}"
  local -a rsync_options
  local fpsync_rsync_options

  rsync_options=(
    -a
    --info=progress2
    --ignore-existing
    --partial-dir=.rsync-partial
    --exclude='*.lock'
    --exclude='*.incomplete'
    --exclude='tmp*'
    --exclude='.rsync-partial/'
  )

  if [[ "${COPY_LINKS_EFFECTIVE}" == "1" ]]; then
    rsync_options+=(--copy-links)
  fi

  fpsync_rsync_options="${rsync_options[*]}"

  case "${COPY_BACKEND}" in
    rsync)
      # 使用 rsync 迁移；同名文件不覆盖，lock/tmp/incomplete 不迁移。
      log "使用 rsync 迁移 Hugging Face datasets cache。"
      if [[ "${COPY_LINKS_EFFECTIVE}" == "1" ]]; then
        log "目标文件系统不支持或不使用 symlink，rsync 将复制 symlink 指向的真实文件。"
      fi
      run rsync \
        "${rsync_options[@]}" \
        "${source_datasets_cache}/" \
        "${target_datasets_cache}/"
      ;;
    fpsync)
      # 使用 fpsync 并行迁移；内部仍通过 rsync 保持复制语义。
      log "使用 fpsync 并行迁移 Hugging Face datasets cache：jobs=${FPSYNC_JOBS}"
      if [[ "${COPY_LINKS_EFFECTIVE}" == "1" ]]; then
        log "目标文件系统不支持或不使用 symlink，fpsync 内部 rsync 将复制 symlink 指向的真实文件。"
      fi
      run fpsync \
        -n "${FPSYNC_JOBS}" \
        -v \
        -o "${fpsync_rsync_options}" \
        "${source_datasets_cache}/" \
        "${target_datasets_cache}/"
      ;;
    *)
      echo "ERROR: COPY_BACKEND must be one of: rsync, fpsync"
      exit 1
      ;;
  esac
}

# 检查命令行参数数量，必须且只能指定一个扫描目录。
log "检查命令行参数数量，必须且只能指定一个扫描目录。"
if [[ "$#" -ne 1 ]]; then
  echo "ERROR: please specify exactly one scan root directory."
  usage
  exit 1
fi

# 从命令行参数读取要扫描的用户目录根路径。
log "从命令行参数读取要扫描的用户目录根路径。"
SCAN_ROOT="${1}"

# 检查复制后端是否合法。
log "检查复制后端是否合法：${COPY_BACKEND}"
case "${COPY_BACKEND}" in
  rsync|fpsync)
    ;;
  *)
    echo "ERROR: COPY_BACKEND must be one of: rsync, fpsync"
    usage
    exit 1
    ;;
esac

# 检查 fpsync 并行数是否为正整数。
log "检查 fpsync 并行数是否为正整数：${FPSYNC_JOBS}"
if [[ ! "${FPSYNC_JOBS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: FPSYNC_JOBS must be a positive integer"
  exit 1
fi

# 检查 symlink 处理策略是否合法。
log "检查 symlink 处理策略是否合法：${COPY_LINKS}"
case "${COPY_LINKS}" in
  auto|yes|no)
    ;;
  *)
    echo "ERROR: COPY_LINKS must be one of: auto, yes, no"
    usage
    exit 1
    ;;
esac

# 检查当前脚本是否以 root 权限运行。
log "检查当前脚本是否以 root 权限运行。"
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: please run as root, for example: sudo ${0} ${SCAN_ROOT}"
  exit 1
fi

# 检查扫描目录是否存在。
log "检查扫描目录是否存在：${SCAN_ROOT}"
if [[ ! -d "${SCAN_ROOT}" ]]; then
  echo "ERROR: scan root does not exist or is not a directory: ${SCAN_ROOT}"
  usage
  exit 1
fi

# 检查 rsync 是否存在。
log "检查 rsync 是否已经安装。"
if ! command -v rsync >/dev/null 2>&1; then
  echo "ERROR: rsync not found. Please install it first."
  echo "Ubuntu/Debian: sudo apt install -y rsync"
  echo "RHEL/Rocky/Alma/Fedora: sudo dnf install -y rsync"
  exit 1
fi

# 如果使用 fpsync，则检查 fpsync 是否存在。
if [[ "${COPY_BACKEND}" == "fpsync" ]]; then
  log "检查 fpsync 是否已经安装。"
  if ! command -v fpsync >/dev/null 2>&1; then
    echo "ERROR: fpsync not found. Please install fpart first."
    echo "Ubuntu/Debian: sudo apt install -y fpart"
    echo "RHEL/Rocky/Alma/Fedora: sudo dnf install -y fpart"
    exit 1
  fi
fi

# 创建目标 Hugging Face datasets cache 目录。
log "创建目标 Hugging Face datasets cache 目录：${TARGET_DATASETS_CACHE}"
run mkdir -p "${TARGET_DATASETS_CACHE}"

# 检测目标文件系统是否支持 symlink。
COPY_LINKS_EFFECTIVE=0
if [[ "${COPY_LINKS}" == "yes" ]]; then
  log "COPY_LINKS=yes，将复制 symlink 指向的真实文件。"
  COPY_LINKS_EFFECTIVE=1
elif [[ "${COPY_LINKS}" == "no" ]]; then
  log "COPY_LINKS=no，将保留 symlink；如果 NAS 不支持 symlink，迁移可能失败。"
else
  symlink_test_target="${TARGET_DATASETS_CACHE}/.symlink-test-target-$$"
  symlink_test_link="${TARGET_DATASETS_CACHE}/.symlink-test-link-$$"
  log "检测目标文件系统是否支持 symlink：${TARGET_DATASETS_CACHE}"
  if [[ "${DRY_RUN}" == "1" ]]; then
    log "DRY_RUN 模式下不实际检测 symlink，默认按支持 symlink 打印命令。"
  else
    printf 'test\n' > "${symlink_test_target}"
    if ln -s "$(basename "${symlink_test_target}")" "${symlink_test_link}" 2>/dev/null; then
      log "目标文件系统支持 symlink，将保留 datasets cache 的 symlink 结构。"
      rm -f "${symlink_test_link}" "${symlink_test_target}"
    else
      warn "目标文件系统不支持 symlink，将复制 symlink 指向的真实文件。"
      rm -f "${symlink_test_link}" "${symlink_test_target}"
      COPY_LINKS_EFFECTIVE=1
    fi
  fi
fi

# 打印迁移参数。
echo "Scan root: ${SCAN_ROOT}"
echo "Target datasets cache: ${TARGET_DATASETS_CACHE}"
echo "Group: ${GROUP}"
echo "Dry run: ${DRY_RUN}"
echo "Copy backend: ${COPY_BACKEND}"
echo "Fpsync jobs: ${FPSYNC_JOBS}"
echo "Copy links mode: ${COPY_LINKS}"
echo "Copy links effective: ${COPY_LINKS_EFFECTIVE}"

# 从 /etc/login.defs 读取普通用户 UID 最小值，仅作为日志参考。
log "从 /etc/login.defs 读取普通用户 UID 最小值。"
uid_min="$(awk '$1 == "UID_MIN" {print $2}' /etc/login.defs 2>/dev/null | tail -n1)"

# 从 /etc/login.defs 读取普通用户 UID 最大值，仅作为日志参考。
log "从 /etc/login.defs 读取普通用户 UID 最大值。"
uid_max="$(awk '$1 == "UID_MAX" {print $2}' /etc/login.defs 2>/dev/null | tail -n1)"

# 如果没有读到 UID_MIN，则默认使用 1000。
uid_min="${uid_min:-1000}"

# 如果没有读到 UID_MAX，则默认使用 60000。
uid_max="${uid_max:-60000}"

# 打印当前系统配置的普通用户 UID 参考范围。
echo "Normal UID reference range: ${uid_min}-${uid_max} (warning only)"

# 定义已处理用户集合，避免同名目录重复处理。
declare -A seen_users=()

# 定义迁移过的用户列表。
migrated_users=()

# 定义跳过的目录列表。
skipped_entries=()

is_login_user() {
  local user="${1}"
  local passwd uid shell

  # 查询系统账号数据库，确认这个用户名真实存在。
  log "查询系统账号数据库，确认用户是否存在：${user}"
  passwd="$(getent passwd "${user}" || true)"

  # 如果系统里没有这个用户，则认为不是合法用户。
  if [[ -z "${passwd}" ]]; then
    log "用户不存在，跳过：${user}"
    return 1
  fi

  # 提取用户 UID。
  uid="$(printf '%s' "${passwd}" | awk -F: '{print $3}')"

  # 提取用户登录 shell。
  shell="$(printf '%s' "${passwd}" | awk -F: '{print $7}')"

  # 检查 UID 是否是数字。
  if [[ ! "${uid}" =~ ^[0-9]+$ ]]; then
    log "用户 UID 不是数字，跳过：${user}, UID=${uid}"
    return 1
  fi

  # 检查 UID 是否处于普通用户参考范围；不在范围内只警告，不跳过。
  if ! (( uid >= uid_min && uid <= uid_max )); then
    log "用户 UID 不在系统普通用户参考范围内，但仍继续处理：${user}, UID=${uid}, reference_range=${uid_min}-${uid_max}"
  fi

  # 排除 nologin、false 或空 shell 的系统账号。
  case "${shell}" in
    */nologin|*/false|"")
      log "用户 shell 不允许登录，跳过：${user}, shell=${shell:-empty}"
      return 1
      ;;
  esac

  # 通过所有检查，认为是合法登录用户。
  log "用户通过合法性检查：${user}, UID=${uid}, shell=${shell}"
  return 0
}

# 查找指定扫描根目录下的一级子目录。
log "查找指定扫描根目录下的一级子目录：${SCAN_ROOT}"
while IFS= read -r -d '' dir; do
  # 从目录路径中取出最后一级名称，作为候选用户名。
  user="$(basename "${dir}")"
  log "处理候选用户目录：${dir}"

  # 跳过 lost+found。
  if [[ "${user}" == "lost+found" ]]; then
    log "跳过 lost+found：${dir}"
    skipped_entries+=("${dir} -> skipped: lost+found")
    continue
  fi

  # 如果这个用户名已经处理过，则跳过。
  if [[ -n "${seen_users[${user}]:-}" ]]; then
    log "用户名已经处理过，跳过重复项：${user}"
    continue
  fi

  # 标记这个用户名已经处理过。
  seen_users["${user}"]=1

  # 如果不是合法登录用户，则跳过。
  if ! is_login_user "${user}"; then
    skipped_entries+=("${dir} -> skipped: not a valid login user")
    continue
  fi

  # 拼接用户本地 Hugging Face datasets cache 目录。
  source_datasets_cache="${dir}/.cache/huggingface/datasets"

  # 如果用户没有本地 Hugging Face datasets cache 目录，则跳过。
  if [[ ! -d "${source_datasets_cache}" ]]; then
    log "用户没有本地 Hugging Face datasets cache，跳过：${source_datasets_cache}"
    skipped_entries+=("${dir} -> skipped: no local huggingface datasets cache")
    continue
  fi

  # 迁移用户本地 Hugging Face datasets cache 到 NAS；同名文件不覆盖，lock/tmp/incomplete 不迁移。
  log "开始迁移用户 Hugging Face datasets cache：user=${user}, source=${source_datasets_cache}, target=${TARGET_DATASETS_CACHE}"
  copy_datasets_cache "${source_datasets_cache}" "${TARGET_DATASETS_CACHE}"

  # 记录已经迁移的用户。
  migrated_users+=("${user}")
done < <(find "${SCAN_ROOT}" -mindepth 1 -maxdepth 1 -type d -print0)

# 修正 NAS datasets cache 的属主属组。
log "修正目标 datasets cache 的属主属组：root:${GROUP}"
run chown -R "root:${GROUP}" "${TARGET_DATASETS_CACHE}"

# 修正 NAS datasets cache 的基础权限：属主和属组可读写，其他用户无权限。
log "修正目标 datasets cache 的基础权限：属主和属组可读写，其他用户无权限。"
run chmod -R u+rwX,g+rwX,o-rwx "${TARGET_DATASETS_CACHE}"

# 给 NAS datasets cache 下所有目录设置 setgid，使后续新文件尽量继承共享组。
log "给目标 datasets cache 下所有目录设置 setgid。"
if [[ "${DRY_RUN}" == "1" ]]; then
  echo "[dry-run] find '${TARGET_DATASETS_CACHE}' -type d -exec chmod 2770 {} +"
else
  find "${TARGET_DATASETS_CACHE}" -type d -exec chmod 2770 {} +
fi

echo
echo "Done."
echo "Users migrated: ${#migrated_users[@]}"
printf '  %s\n' "${migrated_users[@]:-}"

echo
echo "Skipped entries:"
printf '  %s\n' "${skipped_entries[@]:-none}"
