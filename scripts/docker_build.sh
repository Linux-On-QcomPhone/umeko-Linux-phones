#!/usr/bin/env bash
# 本地一键构建（非 GitHub Actions 玩家用）：
#   ./scripts/docker_build.sh devices/wt88047.env
#
# 流程：构建/复用 docker 镜像 → 起特权容器 → 把工作区同步进容器本地 ext4
# （避免 Windows/macOS bind mount 的 IO 惩罚）→ 跑完整流水线 → 把 out/ 拷回来。
#
# 环境变量：
#   PACK_VERSION   产物版本号（默认 local-<日期>）
#   UMERO_IMAGE    镜像名（默认 umeko-build-env）
#   UMERO_CONTAINER 容器名（默认 umeko-build，复用以保留 ccache/.cache）
set -euo pipefail

DEVICE_ENV="${1:?usage: $0 devices/<codename>.env}"
[[ -f "$DEVICE_ENV" ]] || { echo "device config not found: $DEVICE_ENV" >&2; exit 1; }

IMAGE="${UMERO_IMAGE:-umeko-build-env}"
CONTAINER="${UMERO_CONTAINER:-umeko-build}"
PACK_VERSION="${PACK_VERSION:-local-$(date +%Y%m%d)}"

command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }

# --- 1. 镜像 ---------------------------------------------------------------
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "[docker] building image $IMAGE"
    docker build -t "$IMAGE" -f docker/Dockerfile .
fi

# --- 2. 特权容器（chroot/mount 需要 --privileged）----------------------------
if ! docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "[docker] starting privileged container $CONTAINER"
    docker run -d --name "$CONTAINER" --privileged "$IMAGE" tail -f /dev/null >/dev/null
else
    docker start "$CONTAINER" >/dev/null 2>&1 || true
fi

# --- 3. 同步工作区到容器本地 ext4（/work）-------------------------------------
# 不 bind mount 仓库目录：Docker Desktop 的 9p/virtiofs 上编译内核会慢几十倍。
# 排除 .git/build/out；.cache 保留（ubuntu-base tarball、webssh 二进制复用）。
echo "[docker] syncing working tree into container:/work"
tar --exclude=.git --exclude=./build --exclude=./out -cf - . \
    | docker exec -i "$CONTAINER" sh -c 'rm -rf /work && mkdir -p /work && tar -xf - -C /work'

# 容器里构建内核需要 submodule 已就位（随工作区一起同步过去了）。
docker exec "$CONTAINER" bash -c \
    "test -f /work/kernels/msm8916/Makefile || { echo 'kernel submodule missing; run: git submodule update --init' >&2; exit 1; }"

# --- 4. 完整流水线 -----------------------------------------------------------
echo "[docker] running pipeline for $DEVICE_ENV"
docker exec "$CONTAINER" bash -c "
    set -e
    cd /work
    ./scripts/build_kernel.sh '$DEVICE_ENV'
    ./scripts/build_rootfs.sh '$DEVICE_ENV'
    ./scripts/assemble.sh    '$DEVICE_ENV'
    PACK_VERSION='$PACK_VERSION' ./scripts/pack.sh '$DEVICE_ENV'
"

# --- 5. 取回产物 -------------------------------------------------------------
mkdir -p out
docker cp "$CONTAINER:/work/out/." out/
echo "[docker] done. artifacts:"
ls -lh out/
