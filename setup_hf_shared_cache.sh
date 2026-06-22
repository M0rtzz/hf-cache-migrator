#!/usr/bin/env bash
set -euo pipefail

# ===== 配置项：可以通过环境变量覆盖 =====
CACHE_ROOT="${CACHE_ROOT:-/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace}"
GROUP="${GROUP:-hf-users}"
PROFILE_FILE="${PROFILE_FILE:-/etc/profile.d/huggingface-cache.sh}"
USE_POSIX_ACL="${USE_POSIX_ACL:-auto}"
SET_PROFILE_UMASK="${SET_PROFILE_UMASK:-auto}"

# 设置 DRY_RUN=1 时只预览，不实际修改系统。
DRY_RUN="${DRY_RUN:-0}"

usage() {
  echo "Usage: sudo DRY_RUN=1 ${0} /data"
  echo "       sudo ${0} /home"
  echo
  echo "Please specify exactly one scan root directory, for example: /data or /home"
}

log() {
  printf '[INFO] %s\n' "$*"
}

run() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    # 打印将要执行的命令，但不真正执行。
    printf '[dry-run] '

    # 以 shell 安全格式打印命令参数。
    printf '%q ' "$@"

    # 打印换行。
    printf '\n'
  else
    # 实际执行传入的命令。
    "$@"
  fi
}

# 检查命令行参数数量，必须且只能指定一个扫描目录。
log "检查命令行参数数量，必须且只能指定一个扫描目录。"
if [[ "$#" -ne 1 ]]; then
  echo "ERROR: please specify exactly one scan root directory."
  usage
  exit 1
fi

# 检查 POSIX ACL 使用策略是否合法。
log "检查 POSIX ACL 使用策略是否合法：${USE_POSIX_ACL}"
case "${USE_POSIX_ACL}" in
  auto|yes|no)
    ;;
  *)
    echo "ERROR: USE_POSIX_ACL must be one of: auto, yes, no"
    exit 1
    ;;
esac

# 检查是否在 profile 中设置 umask 的策略是否合法。
log "检查是否在 profile 中设置 umask 的策略是否合法：${SET_PROFILE_UMASK}"
case "${SET_PROFILE_UMASK}" in
  auto|always|never)
    ;;
  *)
    echo "ERROR: SET_PROFILE_UMASK must be one of: auto, always, never"
    exit 1
    ;;
esac

# 从命令行参数读取要扫描的用户目录根路径。
log "从命令行参数读取要扫描的用户目录根路径。"
SCAN_ROOT="${1}"

# 检查指定的扫描根目录是否存在。
log "检查指定的扫描根目录是否存在：${SCAN_ROOT}"
if [[ ! -d "${SCAN_ROOT}" ]]; then
  echo "ERROR: scan root does not exist or is not a directory: ${SCAN_ROOT}"
  exit 1
fi

# 检查当前脚本是否以 root 权限运行。
log "检查当前脚本是否以 root 权限运行。"
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: please run as root, for example: sudo bash ${0} ${SCAN_ROOT}"
  exit 1
fi

# 检查系统是否已经安装 setfacl。
log "检查系统是否已经安装 setfacl。"
if ! command -v setfacl >/dev/null 2>&1; then
  echo "ERROR: setfacl not found. Please install acl first."
  echo "Ubuntu/Debian: sudo apt install -y acl"
  echo "RHEL/Rocky/Alma/Fedora: sudo dnf install -y acl"
  echo "Arch: sudo pacman -S --needed acl"
  echo "openSUSE: sudo zypper install -y acl"
  exit 1
fi

# 从 /etc/login.defs 读取普通用户 UID 最小值。
log "从 /etc/login.defs 读取普通用户 UID 最小值。"
uid_min="$(awk '$1 == "UID_MIN" {print $2}' /etc/login.defs 2>/dev/null | tail -n1)"

# 从 /etc/login.defs 读取普通用户 UID 最大值。
log "从 /etc/login.defs 读取普通用户 UID 最大值。"
uid_max="$(awk '$1 == "UID_MAX" {print $2}' /etc/login.defs 2>/dev/null | tail -n1)"

# 如果没有读到 UID_MIN，则默认使用 1000。
log "如果没有读到 UID_MIN，则默认使用 1000。"
uid_min="${uid_min:-1000}"

# 如果没有读到 UID_MAX，则默认使用 60000。
log "如果没有读到 UID_MAX，则默认使用 60000。"
uid_max="${uid_max:-60000}"

# 打印当前系统配置的普通用户 UID 参考范围。
echo "Normal UID reference range: ${uid_min}-${uid_max} (warning only)"

# 打印 Hugging Face 共享缓存目录。
echo "Cache root: ${CACHE_ROOT}"

# 打印共享用户组名称。
echo "Group: ${GROUP}"

# 打印本次扫描的用户目录根路径。
echo "Scan root: ${SCAN_ROOT}"

# 打印 POSIX ACL 使用策略。
echo "POSIX ACL mode: ${USE_POSIX_ACL}"

# 打印 profile umask 设置策略。
echo "Profile umask mode: ${SET_PROFILE_UMASK}"

# 创建共享用户组；如果已经存在则不报错。
log "创建共享用户组；如果已经存在则不报错：${GROUP}"
run groupadd -f "${GROUP}"

# 创建 Hugging Face Hub 模型缓存目录。
log "创建 Hugging Face Hub 模型缓存目录：${CACHE_ROOT}/hub"
run mkdir -p "${CACHE_ROOT}/hub"

# 创建 Hugging Face Datasets 缓存目录。
log "创建 Hugging Face Datasets 缓存目录：${CACHE_ROOT}/datasets"
run mkdir -p "${CACHE_ROOT}/datasets"

# 创建 Hugging Face Assets 缓存目录。
log "创建 Hugging Face Assets 缓存目录：${CACHE_ROOT}/assets"
run mkdir -p "${CACHE_ROOT}/assets"

# 创建 Hugging Face Xet 缓存目录。
log "创建 Hugging Face Xet 缓存目录：${CACHE_ROOT}/xet"
run mkdir -p "${CACHE_ROOT}/xet"

# 将缓存根目录及其内容的属主设为 root，属组设为共享组。
log "将缓存根目录及其内容的属主设为 root，属组设为共享组：${GROUP}"
run chown -R "root:${GROUP}" "${CACHE_ROOT}"

# 设置目录和文件权限：属主和属组可读写，其他用户无权限。
log "设置目录和文件权限：属主和属组可读写，其他用户无权限。"
run chmod -R u+rwX,g+rwX,o-rwx "${CACHE_ROOT}"

# 给所有目录设置 setgid，使新建文件和子目录尽量继承共享组。
log "给所有目录设置 setgid，使新建文件和子目录尽量继承共享组。"
if [[ "${DRY_RUN}" == "1" ]]; then
  echo "[dry-run] find '${CACHE_ROOT}' -type d -exec chmod 2770 {} +"
else
  find "${CACHE_ROOT}" -type d -exec chmod 2770 {} +
fi

# 标记是否已经成功应用 POSIX ACL。
POSIX_ACL_APPLIED=0

# 如果是 dry-run，不实际检测 NAS 是否支持 POSIX ACL。
if [[ "${DRY_RUN}" == "1" ]]; then
  log "DRY_RUN 模式下不实际检测 NAS 是否支持 POSIX ACL。"

  # 如果未禁用 POSIX ACL，则打印正式执行时会尝试的 ACL 命令。
  if [[ "${USE_POSIX_ACL}" != "no" ]]; then
    # 给现有目录和文件设置共享组 ACL 权限。
    log "正式执行时会尝试给现有目录和文件设置共享组 ACL 权限。"
    run setfacl -R -m "g:${GROUP}:rwX,m::rwX" "${CACHE_ROOT}"

    # 设置默认 ACL，使未来新建文件和目录继承共享组读写权限。
    log "正式执行时会尝试设置默认 ACL，使未来新建文件和目录继承共享组读写权限。"
    run setfacl -R -m "d:g:${GROUP}:rwX,d:m::rwX" "${CACHE_ROOT}"
  else
    log "USE_POSIX_ACL=no，跳过 POSIX ACL 设置。"
  fi
else
  # 根据配置决定是否跳过 POSIX ACL。
  if [[ "${USE_POSIX_ACL}" == "no" ]]; then
    log "USE_POSIX_ACL=no，跳过 POSIX ACL 设置。"
  else
    # 创建临时目录，用来检测共享 cache 目录所在文件系统是否支持 POSIX ACL。
    acl_test_dir="${CACHE_ROOT}/.acl-test-$$"
    log "创建临时目录检测 POSIX ACL 支持：${acl_test_dir}"
    mkdir "${acl_test_dir}"

    # 尝试对临时目录设置 POSIX ACL。
    log "尝试对临时目录设置 POSIX ACL。"
    if setfacl -m "g:${GROUP}:rwX,m::rwX" "${acl_test_dir}" >/dev/null 2>&1; then
      # 删除 POSIX ACL 检测临时目录。
      log "POSIX ACL 检测成功，删除临时目录：${acl_test_dir}"
      rmdir "${acl_test_dir}"

      # 给现有目录和文件设置共享组 ACL 权限。
      log "给现有目录和文件设置共享组 ACL 权限。"
      run setfacl -R -m "g:${GROUP}:rwX,m::rwX" "${CACHE_ROOT}"

      # 设置默认 ACL，使未来新建文件和目录继承共享组读写权限。
      log "设置默认 ACL，使未来新建文件和目录继承共享组读写权限。"
      run setfacl -R -m "d:g:${GROUP}:rwX,d:m::rwX" "${CACHE_ROOT}"

      # 记录 POSIX ACL 已经成功应用。
      POSIX_ACL_APPLIED=1
    else
      # 删除 POSIX ACL 检测临时目录。
      log "POSIX ACL 检测失败，删除临时目录：${acl_test_dir}"
      rmdir "${acl_test_dir}" 2>/dev/null || true

      # 如果要求必须使用 POSIX ACL，则直接报错退出。
      if [[ "${USE_POSIX_ACL}" == "yes" ]]; then
        echo "ERROR: ${CACHE_ROOT} does not support POSIX ACL, but USE_POSIX_ACL=yes was set."
        exit 1
      fi

      # 自动模式下 POSIX ACL 不可用时继续执行，并使用 setgid + umask 兜底。
      echo "WARNING: ${CACHE_ROOT} does not support POSIX ACL. Continue with setgid permissions only."
      echo "WARNING: New files may need umask 0002 to stay group-writable across users."
    fi
  fi
fi

# 准备写入 profile 的 umask 配置内容。
profile_umask_content=""

# 根据策略决定是否在 profile 中设置 umask 0002。
case "${SET_PROFILE_UMASK}" in
  always)
    log "SET_PROFILE_UMASK=always，将在 profile 中设置 umask 0002。"
    profile_umask_content='
# Keep files created by login shells group-writable for shared caches.
umask 0002'
    ;;
  auto)
    if [[ "${POSIX_ACL_APPLIED}" == "1" ]]; then
      log "POSIX ACL 已成功应用，profile 中不额外设置 umask。"
    else
      log "POSIX ACL 未成功应用或未检测，profile 中设置 umask 0002 作为兜底。"
      profile_umask_content='
# Keep files created by login shells group-writable for shared caches.
umask 0002'
    fi
    ;;
  never)
    log "SET_PROFILE_UMASK=never，profile 中不设置 umask。"
    ;;
esac

# 生成 /etc/profile.d 中要写入的 Hugging Face 环境变量内容。
log "生成 /etc/profile.d 中要写入的 Hugging Face 环境变量内容。"
profile_content="$(cat <<EOF
# Shared Hugging Face caches on NAS.
# Do not set HF_HOME here, otherwise tokens may move into the shared directory.

export HF_HUB_CACHE=${CACHE_ROOT}/hub
export HF_DATASETS_CACHE=${CACHE_ROOT}/datasets
export HF_ASSETS_CACHE=${CACHE_ROOT}/assets
export HF_XET_CACHE=${CACHE_ROOT}/xet

# Compatibility for older Hugging Face / Transformers versions.
export HUGGINGFACE_HUB_CACHE="\${HF_HUB_CACHE}"
export HUGGINGFACE_ASSETS_CACHE="\${HF_ASSETS_CACHE}"
export TRANSFORMERS_CACHE="\${HF_HUB_CACHE}"

# Keep each user's Hugging Face token private.
export HF_TOKEN_PATH="\${HOME}/.cache/huggingface/token"
${profile_umask_content}
EOF
)"

# 写入全局 Hugging Face 环境变量配置。
log "写入全局 Hugging Face 环境变量配置：${PROFILE_FILE}"
if [[ "${DRY_RUN}" == "1" ]]; then
  echo "[dry-run] write ${PROFILE_FILE}:"
  printf '%s\n' "${profile_content}"
else
  printf '%s\n' "${profile_content}" > "${PROFILE_FILE}"
  log "设置全局 Hugging Face 环境变量配置文件权限为 0644。"
  chmod 0644 "${PROFILE_FILE}"
fi

# 定义已处理用户集合，避免同名目录重复处理。
declare -A seen_users=()

# 定义已加入共享组的用户列表。
added_users=()

# 定义跳过的目录列表。
skipped_entries=()

is_normal_user() {
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
  log "从目录路径中取出最后一级名称，作为候选用户名：${dir}"
  user="$(basename "${dir}")"

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
  log "标记这个用户名已经处理过：${user}"
  seen_users["${user}"]=1

  # 如果不是合法普通登录用户，则跳过。
  log "检查是否为合法普通登录用户：${user}"
  if ! is_normal_user "${user}"; then
    skipped_entries+=("${dir} -> skipped: not a normal valid login user")
    continue
  fi

  # 检查用户是否已经在共享组里。
  log "检查用户是否已经在共享组里：user=${user}, group=${GROUP}"
  if id -nG "${user}" | tr ' ' '\n' | grep -qx "${GROUP}"; then
    echo "Already in group: ${user}"
  else
    # 将用户加入 Hugging Face 共享缓存组。
    log "将用户加入 Hugging Face 共享缓存组：user=${user}, group=${GROUP}"
    run gpasswd -a "${user}" "${GROUP}"

    # 记录本次新增的用户。
    log "记录本次新增的用户：${user}"
    added_users+=("${user}")
  fi
done < <(find "${SCAN_ROOT}" -mindepth 1 -maxdepth 1 -type d -print0)

# 打印空行。
echo

# 打印完成信息。
echo "Done."

# 打印新增用户数量。
echo "Users added to ${GROUP}: ${#added_users[@]}"

# 打印新增用户列表。
printf '  %s\n' "${added_users[@]:-}"

# 打印空行。
echo

# 打印跳过项标题。
echo "Skipped entries:"

# 打印跳过项列表。
printf '  %s\n' "${skipped_entries[@]:-none}"

# 打印空行。
echo

# 提醒用户需要重新登录。
echo "Users need to re-login for group membership and /etc/profile.d env vars to take effect."

# 打印验证命令说明。
echo "Verify as a user with:"

# 打印 Python 验证命令。
echo 'python - <<'"'"'PY'"'"''

# 打印 Python 导入 os 的命令。
echo 'import os'

# 打印 HF_HUB_CACHE 验证语句。
echo 'print(os.getenv("HF_HUB_CACHE"))'

# 打印 HF_DATASETS_CACHE 验证语句。
echo 'print(os.getenv("HF_DATASETS_CACHE"))'

# 打印 HF_TOKEN_PATH 验证语句。
echo 'print(os.getenv("HF_TOKEN_PATH"))'

# 打印 Python heredoc 结束符。
echo 'PY'
