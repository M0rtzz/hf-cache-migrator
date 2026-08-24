# 新建用户接入 Hugging Face 共享缓存指南

本文档说明以后新增 Linux 用户时，如何遵从当前这套 Hugging Face 共享 cache 逻辑。

当前约定：

```text
共享 cache 根目录：/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace
共享用户组：hf-users
本机普通用户组：student
全局环境变量文件：/etc/profile.d/huggingface-cache.sh
用户 token 路径：~/.cache/huggingface/token
```

核心原则：

- 所有用户共用 NAS 上的 Hugging Face cache。
- 每个用户的 Hugging Face Token 仍保留在自己的 home 目录。
- 不设置 `HF_HOME`，避免 token 被放入共享目录。
- 新用户必须加入 `hf-users` 组和本机 `student` 组。
- 新用户必须能读取 `/etc/profile.d/huggingface-cache.sh` 里的环境变量。

## 1. 先确认当前系统状态

查看共享用户组是否存在：

```bash
getent group hf-users
```

查看本机 `student` 组是否存在：

```bash
getent group student
```

查看全局 Hugging Face 环境变量文件：

```bash
cat /etc/profile.d/huggingface-cache.sh
```

期望至少包含：

```bash
export HF_HUB_CACHE=/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/hub
export HF_DATASETS_CACHE=/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/datasets
export HF_ASSETS_CACHE=/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/assets
export HF_XET_CACHE=/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/xet
export HUGGINGFACE_HUB_CACHE="${HF_HUB_CACHE}"
export TRANSFORMERS_CACHE="${HF_HUB_CACHE}"
export HF_TOKEN_PATH="${HOME}/.cache/huggingface/token"
```

当前这台机器还建议保留：

```bash
export HF_HUB_DISABLE_SYMLINKS_WARNING=1
```

原因是 `/nas` 当前是 CIFS/SMB 挂载，不支持 Linux symlink。Hugging Face 仍能工作，只是会复制真实文件，占用更多空间。

查看 `/nas` 挂载类型：

```bash
findmnt -T /nas
```

如果看到类似：

```text
FSTYPE cifs
OPTIONS ... nounix,noperm,file_mode=0777,dir_mode=0777 ...
```

说明 Linux 侧的 `chmod`、`chown`、`setfacl` 可能不会真正控制 NAS 权限。

## 2. 新建一个空用户

下面示例假设新用户叫 `alice`，home 目录放在 `/data/alice`。

先设置变量，避免命令里反复手写用户名：

```bash
NEW_USER=alice
SCAN_ROOT=/data
USER_HOME="${SCAN_ROOT}/${NEW_USER}"
```

检查用户名是否已经存在：

```bash
getent passwd "${NEW_USER}"
```

如果没有输出，说明用户还不存在，可以创建。

创建用户，并把 home 放到 `/data/alice`：

```bash
sudo useradd -m -d "${USER_HOME}" -s /bin/bash "${NEW_USER}"
```

设置用户密码：

```bash
sudo passwd "${NEW_USER}"
```

确认用户、UID、home 和 shell：

```bash
getent passwd "${NEW_USER}"
```

确认 home 目录权限：

```bash
ls -ld "${USER_HOME}"
```

## 3. 把新用户加入 `hf-users` 和 `student` 组

创建共享组；如果已存在不会报错：

```bash
sudo groupadd -f hf-users
```

确认本机 `hf-users` 和 `student` 组存在：

```bash
getent group hf-users
getent group student
```

把新用户同时加入 Hugging Face 共享组和本机普通用户组：

```bash
sudo usermod -aG hf-users,student "${NEW_USER}"
```

也可以使用等价命令：

```bash
sudo gpasswd -a "${NEW_USER}" hf-users
sudo gpasswd -a "${NEW_USER}" student
```

验证用户所在组：

```bash
id "${NEW_USER}"
```

或者只看组名：

```bash
id -nG "${NEW_USER}"
```

注意：组变更通常需要用户重新登录 SSH 后才会在用户 session 里生效。

如果用户已经登录，让他退出后重新 SSH 登录。

## 4. 重新运行初始化脚本，让新用户纳入统一逻辑

进入本仓库：

```bash
cd /data/xzh/Workspaces/Misc/hf-cache-migrator
```

先 dry-run 预览：

```bash
sudo DRY_RUN=1 ./setup_hf_shared_cache.sh /data
```

正式执行：

```bash
sudo ./setup_hf_shared_cache.sh /data
```

这个脚本会做几件事：

- 创建或确认 `hf-users` 组。
- 创建 NAS 上的 `hub`、`datasets`、`assets`、`xet` 目录。
- 写入 `/etc/profile.d/huggingface-cache.sh`。
- 扫描 `/data` 下一级用户目录。
- 跳过 `lost+found`、不存在的系统用户、`nologin` / `false` shell 用户。
- 把合法登录用户加入 `hf-users`。

注意：`setup_hf_shared_cache.sh` 只负责 Hugging Face 共享 cache 组 `hf-users`，不会自动加入本机 `student` 组；`student` 组需要执行前面的 `sudo usermod -aG hf-users,student "${NEW_USER}"`。

如果你的用户 home 在 `/home`，把命令里的 `/data` 换成 `/home`：

```bash
sudo DRY_RUN=1 ./setup_hf_shared_cache.sh /home
sudo ./setup_hf_shared_cache.sh /home
```

## 5. 新用户登录后验证环境变量

让新用户重新 SSH 登录，然后执行：

```bash
python - <<'PY'
import os

print("HF_HUB_CACHE =", os.getenv("HF_HUB_CACHE"))
print("HF_DATASETS_CACHE =", os.getenv("HF_DATASETS_CACHE"))
print("HF_ASSETS_CACHE =", os.getenv("HF_ASSETS_CACHE"))
print("HF_XET_CACHE =", os.getenv("HF_XET_CACHE"))
print("HF_TOKEN_PATH =", os.getenv("HF_TOKEN_PATH"))
print("HUGGINGFACE_HUB_CACHE =", os.getenv("HUGGINGFACE_HUB_CACHE"))
print("TRANSFORMERS_CACHE =", os.getenv("TRANSFORMERS_CACHE"))
PY
```

期望输出类似：

```text
HF_HUB_CACHE = /nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/hub
HF_DATASETS_CACHE = /nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/datasets
HF_ASSETS_CACHE = /nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/assets
HF_XET_CACHE = /nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/xet
HF_TOKEN_PATH = /data/alice/.cache/huggingface/token
HUGGINGFACE_HUB_CACHE = /nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/hub
TRANSFORMERS_CACHE = /nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/hub
```

验证组权限：

```bash
id -nG
```

输出里应该包含：

```text
hf-users
student
```

## 6. 如果新用户使用 zsh

Ubuntu 上 bash 登录 shell 通常会读取 `/etc/profile.d/*.sh`。

但 zsh 登录 shell 不一定读取 `/etc/profile.d/huggingface-cache.sh`。如果新用户用 zsh，并且上面的 Python 验证输出都是 `None`，需要补一个 zsh 入口。

推荐先检查系统级 zsh profile：

```bash
grep -R "huggingface-cache.sh" /etc/zsh /etc/zprofile /etc/zshrc 2>/dev/null
```

如果没有任何输出，可以添加系统级 zsh 入口：

```bash
sudo tee -a /etc/zsh/zprofile >/dev/null <<'EOF'

# Load shared Hugging Face cache environment for zsh login shells.
if [ -r /etc/profile.d/huggingface-cache.sh ]; then
    emulate sh -c '. /etc/profile.d/huggingface-cache.sh'
fi
EOF
```

如果只想给某个用户单独处理，让该用户执行：

```bash
cat >> "${HOME}/.zprofile" <<'EOF'

# Load shared Hugging Face cache environment.
if [ -r /etc/profile.d/huggingface-cache.sh ]; then
    emulate sh -c '. /etc/profile.d/huggingface-cache.sh'
fi
EOF
```

然后重新登录 SSH，再验证环境变量。

## 7. 新用户登录 Hugging Face

新用户自己登录 Hugging Face。不要用 `sudo` 登录，否则 token 会写到 root 的目录。

推荐命令：

```bash
hf auth login
```

非交互环境可以使用：

```bash
export HF_TOKEN=你的_Hugging_Face_Token
hf auth login --token "${HF_TOKEN}"
unset HF_TOKEN
```

登录后验证 token 文件位置：

```bash
ls -l "${HF_TOKEN_PATH}"
```

期望路径是：

```text
/data/alice/.cache/huggingface/token
```

或者：

```text
/home/alice/.cache/huggingface/token
```

不要把 token 放到：

```text
/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace
```

## 8. 新用户下载一个小模型测试

新用户执行：

```bash
python - <<'PY'
from huggingface_hub import snapshot_download

path = snapshot_download("hf-internal-testing/tiny-random-bert")
print(path)
PY
```

期望输出路径在 NAS 共享 cache 下：

```text
/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/hub/models--hf-internal-testing--tiny-random-bert/...
```

再测试只读本地 cache：

```bash
python - <<'PY'
from huggingface_hub import snapshot_download

path = snapshot_download(
    "hf-internal-testing/tiny-random-bert",
    local_files_only=True,
)
print(path)
PY
```

如果 `local_files_only=True` 成功，说明共享 cache 路径可读。

## 9. 如果是迁移已有用户目录

如果新用户不是空用户，而是从旧机器或旧目录迁移来的，可能已经有：

```text
/data/alice/.cache/huggingface/hub
/data/alice/.cache/huggingface/datasets
```

先确认：

```bash
sudo ls -ld "/data/alice/.cache/huggingface/hub" "/data/alice/.cache/huggingface/datasets"
```

迁移 hub cache，先 dry-run：

```bash
cd /data/xzh/Workspaces/Misc/hf-cache-migrator
sudo DRY_RUN=1 COPY_LINKS=yes ./migrate_hf_hub_cache_to_nas.sh /data
```

正式迁移 hub cache：

```bash
sudo COPY_LINKS=yes ./migrate_hf_hub_cache_to_nas.sh /data
```

迁移 datasets cache，先 dry-run：

```bash
sudo DRY_RUN=1 COPY_LINKS=yes ./migrate_hf_datasets_cache_to_nas.sh /data
```

正式迁移 datasets cache：

```bash
sudo COPY_LINKS=yes ./migrate_hf_datasets_cache_to_nas.sh /data
```

如果需要并行迁移，可以使用 `fpsync`：

```bash
sudo COPY_BACKEND=fpsync FPSYNC_JOBS=8 COPY_LINKS=yes ./migrate_hf_hub_cache_to_nas.sh /data
sudo COPY_BACKEND=fpsync FPSYNC_JOBS=8 COPY_LINKS=yes ./migrate_hf_datasets_cache_to_nas.sh /data
```

如果 `/nas` 是 CIFS/SMB，不建议把 `FPSYNC_JOBS` 设置得太大。优先使用 `4` 到 `8`。

## 10. 迁移完成后清理用户本地 cache

清理前先确认新用户已经能从 NAS 使用 cache。

预览清理命令，不会删除：

```bash
sudo EXCLUDE_DIRS=/data/xzh DELETE_DATASETS=1 ./cleanup_local_hf_hub_cache.sh /data
```

正式清理：

```bash
sudo EXCLUDE_DIRS=/data/xzh CONFIRM_DELETE=1 DRY_RUN=0 DELETE_DATASETS=1 ./cleanup_local_hf_hub_cache.sh /data
```

这个命令会删除每个合法用户的：

```text
/data/用户名/.cache/huggingface/hub
/data/用户名/.cache/huggingface/datasets
```

不会删除：

```text
/data/用户名/.cache/huggingface/token
/data/用户名/.cache/huggingface/assets
/data/用户名/.cache/huggingface/xet
```

如果只想删除 `hub`：

```bash
sudo EXCLUDE_DIRS=/data/xzh CONFIRM_DELETE=1 DRY_RUN=0 ./cleanup_local_hf_hub_cache.sh /data
```

如果只想删除 `datasets`：

```bash
sudo EXCLUDE_DIRS=/data/xzh CONFIRM_DELETE=1 DRY_RUN=0 DELETE_HUB=0 DELETE_DATASETS=1 ./cleanup_local_hf_hub_cache.sh /data
```

## 11. 是否需要给新用户单独加 ACL 权限

当前这台机器上，通常不需要，也基本加不上。

原因：

```bash
findmnt -T /nas
```

显示 `/nas` 是 CIFS/SMB 挂载，并且带有：

```text
nounix,noperm,file_mode=0777,dir_mode=0777
```

这意味着：

- POSIX ACL 很可能不支持。
- `setfacl` 可能报 `Operation not supported`。
- Linux 侧 `chmod` / `chown` / `setgid` 对 NAS 权限不一定有效。
- 实际权限应在 NAS 服务端、SMB 共享配置或挂载参数上控制。

所以新用户接入当前方案时，关键动作是：

```bash
sudo usermod -aG hf-users,student "${NEW_USER}"
sudo ./setup_hf_shared_cache.sh /data
```

不建议为每个用户单独执行：

```bash
sudo setfacl -m "u:${NEW_USER}:rwx" /nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace
```

如果未来 `/nas` 换成支持 POSIX ACL 的文件系统，例如 ext4、xfs 或支持 POSIX ACL 的 NFS，可以重新应用 ACL：

```bash
sudo USE_POSIX_ACL=auto ./setup_hf_shared_cache.sh /data
```

验证 ACL：

```bash
getfacl /nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace
```

即使支持 ACL，也建议授权给组 `hf-users`，而不是给每个用户单独加 ACL。

## 12. Gated / Private 模型注意事项

Hugging Face Token 只控制远程下载权限，不控制本地文件读取权限。

如果 `alice` 有权限下载某个 gated/private 模型，模型文件进入共享 NAS cache 后，其他能读共享目录的用户也可能直接读到本地文件。

因此：

- 不要把敏感 gated/private 模型放进全员共享 cache。
- 对敏感模型，建议用户使用自己的私有 cache。
- 或者按项目、课题组、权限等级拆分多个 cache root。
- 真正的隔离必须在 NAS 服务端权限或独立共享目录上实现。

## 13. 新用户标准操作清单

把下面的 `alice` 改成真实用户名。

```bash
NEW_USER=alice
SCAN_ROOT=/data
USER_HOME="${SCAN_ROOT}/${NEW_USER}"
```

创建用户：

```bash
sudo useradd -m -d "${USER_HOME}" -s /bin/bash "${NEW_USER}"
sudo passwd "${NEW_USER}"
```

加入 `hf-users` 和 `student` 组：

```bash
sudo groupadd -f hf-users
getent group hf-users
getent group student
sudo usermod -aG hf-users,student "${NEW_USER}"
```

运行初始化脚本：

```bash
cd /data/xzh/Workspaces/Misc/hf-cache-migrator
sudo DRY_RUN=1 ./setup_hf_shared_cache.sh /data
sudo ./setup_hf_shared_cache.sh /data
```

让用户重新登录 SSH。

用户验证环境：

```bash
python - <<'PY'
import os

print(os.getenv("HF_HUB_CACHE"))
print(os.getenv("HF_DATASETS_CACHE"))
print(os.getenv("HF_TOKEN_PATH"))
PY
```

用户登录 Hugging Face：

```bash
hf auth login
```

用户下载小模型测试：

```bash
python - <<'PY'
from huggingface_hub import snapshot_download

print(snapshot_download("hf-internal-testing/tiny-random-bert"))
PY
```
