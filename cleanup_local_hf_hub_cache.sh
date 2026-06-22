#!/usr/bin/env bash
set -euo pipefail

# ===== 配置项：可以通过环境变量覆盖 =====
DRY_RUN="${DRY_RUN:-1}"
CONFIRM_DELETE="${CONFIRM_DELETE:-0}"
EXCLUDE_DIRS="${EXCLUDE_DIRS:-}"
DELETE_HUB="${DELETE_HUB:-1}"
DELETE_DATASETS="${DELETE_DATASETS:-0}"

usage() {
  echo "Usage:"
  echo "  sudo ${0} /data"
  echo "  sudo DRY_RUN=1 ${0} /home"
  echo "  sudo CONFIRM_DELETE=1 DRY_RUN=0 ${0} /data"
  echo "  sudo EXCLUDE_DIRS=/data/xzh:/data/yy ${0} /data"
  echo "  sudo DELETE_DATASETS=1 ${0} /data"
  echo "  sudo DELETE_HUB=0 DELETE_DATASETS=1 ${0} /data"
  echo
  echo "Please specify exactly one scan root directory, for example: /data or /home"
}

log() {
  printf '[INFO] %s\n' "$*"
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

is_excluded_dir() {
  local dir="${1}"
  local exclude_dir

  # EXCLUDE_DIRS 使用冒号分隔多个绝对路径，例如：/data/xzh:/data/yy
  [[ -n "${EXCLUDE_DIRS}" ]] || return 1

  IFS=':' read -r -a exclude_dirs_array <<< "${EXCLUDE_DIRS}"
  for exclude_dir in "${exclude_dirs_array[@]}"; do
    [[ -n "${exclude_dir}" ]] || continue
    if [[ "${dir}" == "${exclude_dir}" ]]; then
      return 0
    fi
  done

  return 1
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

# 检查 DRY_RUN 参数是否合法。
log "检查 DRY_RUN 参数是否合法：${DRY_RUN}"
case "${DRY_RUN}" in
  0|1)
    ;;
  *)
    echo "ERROR: DRY_RUN must be 0 or 1"
    exit 1
    ;;
esac

# 检查 CONFIRM_DELETE 参数是否合法。
log "检查 CONFIRM_DELETE 参数是否合法：${CONFIRM_DELETE}"
case "${CONFIRM_DELETE}" in
  0|1)
    ;;
  *)
    echo "ERROR: CONFIRM_DELETE must be 0 or 1"
    exit 1
    ;;
esac

# 检查 DELETE_HUB 参数是否合法。
log "检查 DELETE_HUB 参数是否合法：${DELETE_HUB}"
case "${DELETE_HUB}" in
  0|1)
    ;;
  *)
    echo "ERROR: DELETE_HUB must be 0 or 1"
    exit 1
    ;;
esac

# 检查 DELETE_DATASETS 参数是否合法。
log "检查 DELETE_DATASETS 参数是否合法：${DELETE_DATASETS}"
case "${DELETE_DATASETS}" in
  0|1)
    ;;
  *)
    echo "ERROR: DELETE_DATASETS must be 0 or 1"
    exit 1
    ;;
esac

# 至少需要选择一个要删除的 Hugging Face cache 目录。
if [[ "${DELETE_HUB}" == "0" && "${DELETE_DATASETS}" == "0" ]]; then
  echo "ERROR: nothing to delete. Set DELETE_HUB=1 and/or DELETE_DATASETS=1."
  exit 1
fi

# 默认只预览；正式删除必须显式设置 CONFIRM_DELETE=1 且 DRY_RUN=0。
if [[ "${DRY_RUN}" == "0" && "${CONFIRM_DELETE}" != "1" ]]; then
  echo "ERROR: refusing to delete without CONFIRM_DELETE=1."
  echo "Run preview first: sudo ${0} ${SCAN_ROOT}"
  echo "Delete for real: sudo CONFIRM_DELETE=1 DRY_RUN=0 ${0} ${SCAN_ROOT}"
  exit 1
fi

# 打印清理参数。
echo "Scan root: ${SCAN_ROOT}"
echo "Dry run: ${DRY_RUN}"
echo "Confirm delete: ${CONFIRM_DELETE}"
echo "Exclude dirs: ${EXCLUDE_DIRS:-none}"
echo "Delete hub: ${DELETE_HUB}"
echo "Delete datasets: ${DELETE_DATASETS}"

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

# 定义已删除或将删除 hub cache 的用户列表。
deleted_hub_users=()

# 定义已删除或将删除 datasets cache 的用户列表。
deleted_datasets_users=()

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

  # 如果目录在排除列表中，则跳过。
  if is_excluded_dir "${dir}"; then
    log "目录在排除列表中，跳过：${dir}"
    skipped_entries+=("${dir} -> skipped: excluded by EXCLUDE_DIRS")
    continue
  fi

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

  deleted_any=0

  # 拼接用户本地 Hugging Face hub cache 目录；这正是 hub 迁移脚本的源目录。
  local_hub_cache="${dir}/.cache/huggingface/hub"

  # 如果启用了 hub 清理，则删除用户本地 Hugging Face hub cache 目录。
  if [[ "${DELETE_HUB}" == "1" ]]; then
    if [[ -d "${local_hub_cache}" ]]; then
      # 删除用户本地 Hugging Face hub cache 目录；不删除 token 和其他 Hugging Face cache。
      log "删除用户本地 Hugging Face hub cache：user=${user}, path=${local_hub_cache}"
      run rm -rf "${local_hub_cache}"

      # 记录已删除或将删除 hub cache 的用户。
      deleted_hub_users+=("${user}")
      deleted_any=1
    else
      log "用户没有本地 Hugging Face hub cache，跳过：${local_hub_cache}"
    fi
  fi

  # 拼接用户本地 Hugging Face datasets cache 目录；这正是 datasets 迁移脚本的源目录。
  local_datasets_cache="${dir}/.cache/huggingface/datasets"

  # 如果启用了 datasets 清理，则删除用户本地 Hugging Face datasets cache 目录。
  if [[ "${DELETE_DATASETS}" == "1" ]]; then
    if [[ -d "${local_datasets_cache}" ]]; then
      # 删除用户本地 Hugging Face datasets cache 目录；不删除 token、hub、assets、xet。
      log "删除用户本地 Hugging Face datasets cache：user=${user}, path=${local_datasets_cache}"
      run rm -rf "${local_datasets_cache}"

      # 记录已删除或将删除 datasets cache 的用户。
      deleted_datasets_users+=("${user}")
      deleted_any=1
    else
      log "用户没有本地 Hugging Face datasets cache，跳过：${local_datasets_cache}"
    fi
  fi

  # 如果本用户没有任何选中的 cache 目录，则记录为跳过。
  if [[ "${deleted_any}" == "0" ]]; then
    skipped_entries+=("${dir} -> skipped: no selected local huggingface cache")
  fi
done < <(find "${SCAN_ROOT}" -mindepth 1 -maxdepth 1 -type d -print0)

echo
echo "Done."
if [[ "${DRY_RUN}" == "1" ]]; then
  echo "Users whose hub cache would be cleaned: ${#deleted_hub_users[@]}"
else
  echo "Users whose hub cache was cleaned: ${#deleted_hub_users[@]}"
fi
printf '  %s\n' "${deleted_hub_users[@]:-}"

echo
if [[ "${DRY_RUN}" == "1" ]]; then
  echo "Users whose datasets cache would be cleaned: ${#deleted_datasets_users[@]}"
else
  echo "Users whose datasets cache was cleaned: ${#deleted_datasets_users[@]}"
fi
printf '  %s\n' "${deleted_datasets_users[@]:-}"

echo
echo "Skipped entries:"
printf '  %s\n' "${skipped_entries[@]:-none}"
