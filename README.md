# Shared Hugging Face Cache Tools

一组用于多用户 Linux 服务器的 Hugging Face 共享缓存脚本。目标是把模型、数据集和下游资源缓存统一放到 NAS，例如：

```text
/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace
```

同时保留每个用户自己的 Hugging Face Token：

```text
~/.cache/huggingface/token
```

脚本适合 `/data/用户名` 或 `/home/用户名` 这类多用户目录结构。

## 功能

- 初始化共享 Hugging Face cache 目录。
- 创建并维护共享用户组，默认是 `hf-users`。
- 为所有合法登录用户写入全局 Hugging Face 环境变量。
- 迁移已有用户的 `hub` cache 到 NAS。
- 迁移已有用户的 `datasets` cache 到 NAS。
- 清理已经迁移后的本地 `hub` 和 `datasets` cache。
- 支持 `rsync` 稳定复制，也支持 `fpsync` 并行复制。
- 支持 dry-run 预览，避免误删或误迁移。

## 文件

```text
setup_hf_shared_cache.sh
migrate_hf_hub_cache_to_nas.sh
migrate_hf_datasets_cache_to_nas.sh
cleanup_local_hf_hub_cache.sh
NEW_USER_GUIDE.md
```

### `setup_hf_shared_cache.sh`

初始化共享缓存目录、用户组和 `/etc/profile.d/huggingface-cache.sh`。

默认写入这些环境变量：

```bash
export HF_HUB_CACHE=/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/hub
export HF_DATASETS_CACHE=/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/datasets
export HF_ASSETS_CACHE=/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/assets
export HF_XET_CACHE=/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/xet

export HUGGINGFACE_HUB_CACHE="${HF_HUB_CACHE}"
export HUGGINGFACE_ASSETS_CACHE="${HF_ASSETS_CACHE}"
export TRANSFORMERS_CACHE="${HF_HUB_CACHE}"

export HF_TOKEN_PATH="${HOME}/.cache/huggingface/token"
```

注意：脚本不会设置 `HF_HOME`，否则 token 可能被放进共享目录。

### `migrate_hf_hub_cache_to_nas.sh`

迁移每个用户的：

```text
~/.cache/huggingface/hub
```

到：

```text
/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/hub
```

### `migrate_hf_datasets_cache_to_nas.sh`

迁移每个用户的：

```text
~/.cache/huggingface/datasets
```

到：

```text
/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/datasets
```

### `cleanup_local_hf_hub_cache.sh`

删除已经迁移后的用户本地 cache。默认只删除 `hub`，可通过参数同时删除 `datasets`。

这个脚本默认是 dry-run，不会直接删除。真实删除必须同时设置：

```bash
CONFIRM_DELETE=1 DRY_RUN=0
```

## 安装依赖

Ubuntu / Debian：

```bash
sudo apt update
sudo apt install -y acl rsync
```

如果要使用 `fpsync` 并行迁移：

```bash
sudo apt install -y fpart
```

RHEL / Rocky / Alma / Fedora：

```bash
sudo dnf install -y acl rsync
sudo dnf install -y fpart
```

## 快速开始

### 1. 初始化共享 cache

先 dry-run 预览：

```bash
sudo DRY_RUN=1 ./setup_hf_shared_cache.sh /data
```

正式执行：

```bash
sudo ./setup_hf_shared_cache.sh /data
```

也可以扫描 `/home`：

```bash
sudo ./setup_hf_shared_cache.sh /home
```

脚本要求必须指定且只能指定一个扫描目录。不指定会报错。

### 2. 让用户环境变量生效

新登录的 SSH session 会自动读取 `/etc/profile.d/huggingface-cache.sh`。

当前 shell 可以手动执行：

```bash
source /etc/profile.d/huggingface-cache.sh
```

验证：

```bash
python - <<'PY'
import os

print(os.getenv("HF_HUB_CACHE"))
print(os.getenv("HF_DATASETS_CACHE"))
print(os.getenv("HF_TOKEN_PATH"))
PY
```

期望输出类似：

```text
/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/hub
/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/datasets
/home/alice/.cache/huggingface/token
```

如果用户使用 zsh，并且重新登录后环境变量仍然是 `None`，说明 zsh 没有读取 `/etc/profile.d/huggingface-cache.sh`。先检查是否已经配置过：

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

然后让 zsh 用户重新 SSH 登录，再执行上面的 Python 验证命令。

测试 bash 用户登录后是否正常，可以用目标用户启动 login shell：

```bash
sudo -iu alice bash -lc 'env | grep -E "^(HF_HUB_CACHE|HF_DATASETS_CACHE|HF_TOKEN_PATH)="'
```

如果想用 Python 验证，使用单行命令，避免嵌套 heredoc 引号问题：

```bash
sudo -iu alice bash -lc 'python -c "import os; print(os.getenv(\"HF_HUB_CACHE\")); print(os.getenv(\"HF_DATASETS_CACHE\")); print(os.getenv(\"HF_TOKEN_PATH\"))"'
```

也可以直接通过 SSH 登录该用户后执行：

```bash
echo "${SHELL}"
python - <<'PY'
import os

print(os.getenv("HF_HUB_CACHE"))
print(os.getenv("HF_DATASETS_CACHE"))
print(os.getenv("HF_TOKEN_PATH"))
PY
```

如果输出是 `None`，先检查用户 shell 和 profile 文件：

```bash
getent passwd alice
ls -l /etc/profile.d/huggingface-cache.sh
bash -lc 'echo "${HF_HUB_CACHE}"; echo "${HF_DATASETS_CACHE}"; echo "${HF_TOKEN_PATH}"'
```

### 3. 迁移 hub cache

先 dry-run：

```bash
sudo DRY_RUN=1 ./migrate_hf_hub_cache_to_nas.sh /data
```

稳定迁移，默认使用 `rsync`：

```bash
sudo COPY_LINKS=yes ./migrate_hf_hub_cache_to_nas.sh /data
```

并行迁移，适合本地盘或性能较好的 NAS：

```bash
sudo COPY_BACKEND=fpsync FPSYNC_JOBS=8 COPY_LINKS=yes ./migrate_hf_hub_cache_to_nas.sh /data
```

如果 `/nas` 是 CIFS/SMB 网络盘，不建议把 `FPSYNC_JOBS` 设得太高。通常 `4` 到 `8` 比 `64` 更稳。

### 4. 迁移 datasets cache

先 dry-run：

```bash
sudo DRY_RUN=1 ./migrate_hf_datasets_cache_to_nas.sh /data
```

稳定迁移：

```bash
sudo COPY_LINKS=yes ./migrate_hf_datasets_cache_to_nas.sh /data
```

并行迁移：

```bash
sudo COPY_BACKEND=fpsync FPSYNC_JOBS=8 COPY_LINKS=yes ./migrate_hf_datasets_cache_to_nas.sh /data
```

`datasets` cache 往往包含大量小文件。对 CIFS/SMB NAS 来说，并行太高会导致 `ls /nas`、`du`、`find` 都变慢。

### 5. 验证共享 cache 是否生效

测试一个很小的公开模型：

```bash
source /etc/profile.d/huggingface-cache.sh

python - <<'PY'
from huggingface_hub import snapshot_download

path = snapshot_download("hf-internal-testing/tiny-random-bert")
print(path)
PY
```

如果成功，路径应该在：

```text
/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/hub
```

测试只读本地 cache：

```bash
source /etc/profile.d/huggingface-cache.sh

python - <<'PY'
from huggingface_hub import snapshot_download

path = snapshot_download("hf-internal-testing/tiny-random-bert", local_files_only=True)
print(path)
PY
```

测试一个公开数据集 repo：

```bash
source /etc/profile.d/huggingface-cache.sh

python - <<'PY'
from huggingface_hub import snapshot_download

path = snapshot_download(
    "openai/gsm8k",
    repo_type="dataset",
    local_files_only=True,
)
print(path)
PY
```

## 清理本地 cache

先预览。下面命令不会删除，因为默认 `DRY_RUN=1`：

```bash
sudo EXCLUDE_DIRS=/data/xzh DELETE_DATASETS=1 ./cleanup_local_hf_hub_cache.sh /data
```

正式删除：

```bash
sudo EXCLUDE_DIRS=/data/xzh CONFIRM_DELETE=1 DRY_RUN=0 DELETE_DATASETS=1 ./cleanup_local_hf_hub_cache.sh /data
```

只删除 `hub`：

```bash
sudo EXCLUDE_DIRS=/data/xzh CONFIRM_DELETE=1 DRY_RUN=0 ./cleanup_local_hf_hub_cache.sh /data
```

只删除 `datasets`：

```bash
sudo EXCLUDE_DIRS=/data/xzh CONFIRM_DELETE=1 DRY_RUN=0 DELETE_HUB=0 DELETE_DATASETS=1 ./cleanup_local_hf_hub_cache.sh /data
```

`EXCLUDE_DIRS` 使用冒号分隔多个目录：

```bash
sudo EXCLUDE_DIRS=/data/xzh:/data/yy DELETE_DATASETS=1 ./cleanup_local_hf_hub_cache.sh /data
```

清理脚本只删除：

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

## 参数说明

### 通用扫描目录

所有脚本都要求指定一个扫描根目录，例如：

```bash
./script.sh /data
./script.sh /home
```

脚本只扫描一级子目录，并用目录名作为候选用户名。

会跳过：

- `lost+found`
- 系统账号数据库里不存在的用户
- shell 是 `nologin` 或 `false` 的账号
- 重复用户名

UID 不在 `/etc/login.defs` 的普通用户范围内时只警告，不跳过。

### 初始化脚本参数

```bash
CACHE_ROOT=/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace
GROUP=hf-users
PROFILE_FILE=/etc/profile.d/huggingface-cache.sh
USE_POSIX_ACL=auto
SET_PROFILE_UMASK=auto
DRY_RUN=0
```

`USE_POSIX_ACL` 可选值：

```text
auto
yes
no
```

`SET_PROFILE_UMASK` 可选值：

```text
auto
always
never
```

### 迁移脚本参数

hub 迁移：

```bash
TARGET_HUB_CACHE=/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/hub
GROUP=hf-users
DRY_RUN=0
COPY_BACKEND=rsync
FPSYNC_JOBS=8
COPY_LINKS=auto
```

datasets 迁移：

```bash
TARGET_DATASETS_CACHE=/nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace/datasets
GROUP=hf-users
DRY_RUN=0
COPY_BACKEND=rsync
FPSYNC_JOBS=8
COPY_LINKS=auto
```

`COPY_BACKEND` 可选值：

```text
rsync
fpsync
```

`COPY_LINKS` 可选值：

```text
auto
yes
no
```

如果目标 NAS 不支持 symlink，建议：

```bash
COPY_LINKS=yes
```

这样迁移时会复制 symlink 指向的真实文件，而不是在 NAS 上创建 symlink。

### 清理脚本参数

```bash
DRY_RUN=1
CONFIRM_DELETE=0
EXCLUDE_DIRS=
DELETE_HUB=1
DELETE_DATASETS=0
```

正式删除必须显式设置：

```bash
CONFIRM_DELETE=1 DRY_RUN=0
```

## 迁移语义

迁移脚本使用：

```text
--ignore-existing
```

也就是 NAS 上已经存在的同名文件不会被覆盖。

同时排除：

```text
*.lock
*.incomplete
tmp*
.rsync-partial/
```

并使用：

```text
--partial-dir=.rsync-partial
```

中断时，未完成文件会尽量留在 `.rsync-partial` 中，而不是直接留下一个同名坏文件。

## NAS / CIFS / SMB 注意事项

很多 NAS 使用 CIFS/SMB 挂载，例如：

```text
//192.168.x.x/data on /nas type cifs
```

这种环境可能有几个限制：

- 不支持 POSIX ACL。
- 不支持 Linux symlink。
- `chown`、`chmod`、`setgid` 可能不会真正生效。
- 大量小文件并发写入时，`ls /nas`、`find /nas`、`du /nas` 会明显变慢。

如果 NAS 不支持 symlink，Hugging Face 仍然可以工作，但会退化为复制真实文件，可能占用更多空间。可以用下面变量关闭警告：

```bash
export HF_HUB_DISABLE_SYMLINKS_WARNING=1
```

如果需要严格权限隔离，必须在 NAS 服务端、共享目录、导出规则或挂载参数层面解决。仅靠 Linux 客户端上的 `chmod`、`chown`、`setfacl` 不一定有效。

## Gated / Private 模型风险

共享 cache 的本质是：只要一个用户把模型文件下载进共享目录，其他能读共享目录的用户就可能直接读取这些本地文件。

因此：

- 不要把 gated/private 模型放进全员可读的共享 cache。
- 如果需要共享 gated/private 模型，建议按项目或权限组拆分不同 cache root。
- 对敏感模型，建议让用户继续使用自己的私有本地 cache。
- NAS 权限必须在服务端严格隔离，不能只依赖 Hugging Face token。

Hugging Face token 只控制远程下载权限，不控制本地文件读取权限。

## 常用排查命令

查看当前环境变量：

```bash
python - <<'PY'
import os

for key in [
    "HF_HUB_CACHE",
    "HF_DATASETS_CACHE",
    "HF_ASSETS_CACHE",
    "HF_XET_CACHE",
    "HF_TOKEN_PATH",
    "HUGGINGFACE_HUB_CACHE",
    "TRANSFORMERS_CACHE",
]:
    print(key, "=", os.getenv(key))
PY
```

查看 `/nas` 挂载类型：

```bash
findmnt -T /nas
```

查看是否还有迁移进程：

```bash
ps -eo pid,ppid,stat,etime,comm,args | grep -E 'rsync|fpsync|fpart' | grep -v grep
```

查看 NAS cache 目录：

```bash
ls -lah /nas/DO_NOT_EDIT_OR_DELETE_SHARED_CACHE/HuggingFace
```

如果 `/nas` 很卡，避免递归命令：

```bash
ls -lR /nas
du -sh /nas/*
find /nas ...
```

## 推荐执行顺序

```bash
sudo DRY_RUN=1 ./setup_hf_shared_cache.sh /data
sudo ./setup_hf_shared_cache.sh /data

sudo DRY_RUN=1 COPY_LINKS=yes ./migrate_hf_hub_cache_to_nas.sh /data
sudo COPY_LINKS=yes ./migrate_hf_hub_cache_to_nas.sh /data

sudo DRY_RUN=1 COPY_LINKS=yes ./migrate_hf_datasets_cache_to_nas.sh /data
sudo COPY_LINKS=yes ./migrate_hf_datasets_cache_to_nas.sh /data

sudo EXCLUDE_DIRS=/data/xzh DELETE_DATASETS=1 ./cleanup_local_hf_hub_cache.sh /data
sudo EXCLUDE_DIRS=/data/xzh CONFIRM_DELETE=1 DRY_RUN=0 DELETE_DATASETS=1 ./cleanup_local_hf_hub_cache.sh /data
```
