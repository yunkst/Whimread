#!/usr/bin/env bash
# Whimread CloudBase PG migration 脚本
#
# 用法: ./scripts/cloudbase/migrate.sh dev
#
# 注意:
# - 不会自动跑 managePgDatabase(MCP-only);CLI 用户手动跑 SQL
# - MCP 用户用 managePgDatabase(action=applyMigration, envId=$ENV_ID, ...) 逐个文件应用

set -euo pipefail

ENV_NAME="${1:-dev}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MIGRATIONS_DIR="$ROOT_DIR/cloudbase/migrations"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }

# shellcheck source=/dev/null
source "$ROOT_DIR/.env"

case "$ENV_NAME" in
    dev)     ENV_ID="${TCB_ENV_ID_DEV}" ;;
    staging) ENV_ID="${TCB_ENV_ID_STAGING}" ;;
    prod)    ENV_ID="${TCB_ENV_ID_PROD}" ;;
    *) echo "Unknown env: $ENV_NAME"; exit 1 ;;
esac

if [[ -z "$ENV_ID" ]]; then
    echo "未配置 $ENV_NAME 的 EnvId"
    exit 1
fi

log_info "EnvId: $ENV_ID"
log_info "Migration 文件:"
ls -1 "$MIGRATIONS_DIR"/*.sql | while read -r f; do
    echo "  - $(basename "$f")"
done

log_warn "本脚本只打印待应用的 migration 列表。"
log_warn "实际应用请用以下任一方式:"
echo
echo "  方式 A:MCP(推荐)"
echo "    managePgDatabase(action=applyMigration, envId=$ENV_ID,"
echo "                     migrationName=\"create_devices\","
echo "                     migrationVersion=\"20260907120001\","
echo "                     sql=\"<读取 $(ls $MIGRATIONS_DIR/20260907120001_*.sql)>\","
echo "                     confirm=true)"
echo
echo "  方式 B:CLI + MCP 数据平面"
echo "    cat $MIGRATIONS_DIR/20260907120001_create_devices.sql | \\"
echo "      callCloudApi(service=tcb, action=ExecutePGSql, params=...)"
echo
echo "  方式 C:CloudBase 控制台 SQL 编辑器"
echo "    https://tcb.cloud.tencent.com/dev?envId=$ENV_ID#/db/mysql"
echo

# 打印每个 SQL 文件内容(供复制粘贴)
for f in "$MIGRATIONS_DIR"/*.sql; do
    log_info "===== $(basename "$f") ====="
    cat "$f"
    echo
done
