#!/usr/bin/env bash
# Whimread CloudBase 一键部署脚本
#
# 用法:
#   1. 复制 .env.example 为 .env,填入 EnvId / JWT 公私钥 / LLM Key
#   2. ./scripts/cloudbase/deploy.sh dev        # 部署到 whimread-dev
#   3. ./scripts/cloudbase/deploy.sh staging    # 部署到 whimread-staging
#   4. ./scripts/cloudbase/deploy.sh prod       # 部署到 whimread-prod
#
# 前置条件:
#   - 已安装 @cloudbase/cli: npm i -g @cloudbase/cli
#   - 已登录: tcb login
#   - 已创建 env: tcb env create --alias whimread-dev --package baas_personal --postgresql --yes
#
# 来源参考:[Skill: cloudbase-cli/SKILL.md] 显式带 EnvId,禁用 tcb deploy

set -euo pipefail

ENV_NAME="${1:-dev}"   # dev | staging | prod
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ============================================
# 0. 前置检查
# ============================================
log_info "Whimread CloudBase 部署 -> $ENV_NAME"

if [[ ! -f "$ENV_FILE" ]]; then
    log_error "未找到 .env 文件,请复制 .env.example 为 .env 并填写"
    exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

# 根据 ENV_NAME 选择 EnvId 和 LLM 配置
case "$ENV_NAME" in
    dev)
        ENV_ID="${TCB_ENV_ID_DEV:?TCB_ENV_ID_DEV 未设置}"
        LLM_BASE_URL="${LLM_BASE_URL_DEV:-https://api.deepseek.com/v1}"
        LLM_DEFAULT_MODEL="${LLM_DEFAULT_MODEL_DEV:-deepseek-chat}"
        ;;
    staging)
        ENV_ID="${TCB_ENV_ID_STAGING:?TCB_ENV_ID_STAGING 未设置}"
        LLM_BASE_URL="${LLM_BASE_URL_STAGING:-https://api.deepseek.com/v1}"
        LLM_DEFAULT_MODEL="${LLM_DEFAULT_MODEL_STAGING:-deepseek-chat}"
        ;;
    prod)
        ENV_ID="${TCB_ENV_ID_PROD:?TCB_ENV_ID_PROD 未设置}"
        LLM_BASE_URL="${LLM_BASE_URL_PROD:-https://api.deepseek.com/v1}"
        LLM_DEFAULT_MODEL="${LLM_DEFAULT_MODEL_PROD:-deepseek-chat}"
        ;;
    *)
        log_error "未知环境名: $ENV_NAME (应为 dev | staging | prod)"
        exit 1
        ;;
esac

log_info "目标 EnvId: $ENV_ID"
log_info "LLM Base URL: $LLM_BASE_URL"
log_info "LLM Default Model: $LLM_DEFAULT_MODEL"

# 检查 tcb CLI
if ! command -v tcb &> /dev/null; then
    log_error "未找到 tcb 命令,请先安装: npm i -g @cloudbase/cli"
    exit 1
fi

# 检查登录态
if ! tcb env list &> /dev/null; then
    log_warn "未登录,尝试 tcb login..."
    tcb login
fi

# ============================================
# 读取 PEM 密钥文件(多行内容用文件引用,避免转义问题)
# ============================================
if [[ -n "${DEVICE_JWT_PRIVATE_KEY_FILE:-}" ]]; then
    KEY_FILE="$ROOT_DIR/${DEVICE_JWT_PRIVATE_KEY_FILE#./}"
    if [[ -f "$KEY_FILE" ]]; then
        DEVICE_JWT_PRIVATE_KEY="$(cat "$KEY_FILE")"
    else
        log_error "JWT 私钥文件不存在: $KEY_FILE"
        exit 1
    fi
fi
if [[ -n "${DEVICE_JWT_PUBLIC_KEY_FILE:-}" ]]; then
    PUB_FILE="$ROOT_DIR/${DEVICE_JWT_PUBLIC_KEY_FILE#./}"
    if [[ -f "$PUB_FILE" ]]; then
        DEVICE_JWT_PUBLIC_KEY="$(cat "$PUB_FILE")"
    else
        log_error "JWT 公钥文件不存在: $PUB_FILE"
        exit 1
    fi
fi
if [[ -z "${DEVICE_JWT_PRIVATE_KEY:-}" || -z "${DEVICE_JWT_PUBLIC_KEY:-}" ]]; then
    log_error "JWT 公私钥未配置(检查 .env 的 DEVICE_JWT_*_KEY_FILE)"
    exit 1
fi

# ============================================
# 1. 应用 PG migrations
# ============================================
log_info "==> 步骤 1/4: 应用 PG migrations"
"$SCRIPT_DIR/migrate.sh" "$ENV_NAME"

# ============================================
# 2. 部署 device-auth 函数
# ============================================
log_info "==> 步骤 2/4: 部署 device-auth"
cd "$ROOT_DIR/cloudfunctions/device-auth"
[[ -d node_modules ]] || npm install --omit=dev

tcb fn deploy device-auth -e "$ENV_ID"
tcb fn config update device-auth -e "$ENV_ID" \
    --env "{
        \"DEVICE_JWT_PRIVATE_KEY\": \"${DEVICE_JWT_PRIVATE_KEY}\",
        \"DEVICE_JWT_PUBLIC_KEY\": \"${DEVICE_JWT_PUBLIC_KEY}\",
        \"GITHUB_STAR_REPO\": \"${GITHUB_STAR_REPO:-}\",
        \"GITHUB_TOKEN\": \"${GITHUB_TOKEN:-}\",
        \"STAR_REDEEM_AMOUNT\": \"${STAR_REDEEM_AMOUNT:-50}\",
        \"TCB_ENV_ID\": \"${ENV_ID}\"
    }"

# ============================================
# 3. 部署 app-release 函数
# ============================================
log_info "==> 步骤 3/4: 部署 app-release"
cd "$ROOT_DIR/cloudfunctions/app-release"
[[ -d node_modules ]] || npm install --omit=dev

tcb fn deploy app-release -e "$ENV_ID"
tcb fn config update app-release -e "$ENV_ID" \
    --env "{
        \"TCB_ENV_ID\": \"${ENV_ID}\"
    }"

# ============================================
# 4. 部署 llm-proxy 函数 + 注入 LLM Key
# ============================================
log_info "==> 步骤 4/4: 部署 llm-proxy"
cd "$ROOT_DIR/cloudfunctions/llm-proxy"
[[ -d node_modules ]] || npm install --omit=dev

tcb fn deploy llm-proxy -e "$ENV_ID"
tcb fn config update llm-proxy -e "$ENV_ID" \
    --env "{
        \"LLM_BASE_URL\": \"${LLM_BASE_URL}\",
        \"LLM_API_KEY\": \"${LLM_API_KEY:-PLACEHOLDER_NOT_SET}\",
        \"LLM_DEFAULT_MODEL\": \"${LLM_DEFAULT_MODEL}\",
        \"DEVICE_JWT_PUBLIC_KEY\": \"${DEVICE_JWT_PUBLIC_KEY}\",
        \"TCB_ENV_ID\": \"${ENV_ID}\"
    }"

# ============================================
# 5. 部署 feedback 函数 + 注入 admin/JWT 公钥
# ============================================
log_info "==> 步骤 5/5: 部署 feedback"
cd "$ROOT_DIR/cloudfunctions/feedback"
[[ -d node_modules ]] || npm install --omit=dev

tcb fn deploy feedback -e "$ENV_ID"
tcb fn config update feedback -e "$ENV_ID" \
    --env "{
        \"DEVICE_JWT_PUBLIC_KEY\": \"${DEVICE_JWT_PUBLIC_KEY}\",
        \"TCB_ENV_ID\": \"${ENV_ID}\",
        \"PUBLISH_API_TOKEN\": \"${PUBLISH_API_TOKEN}\"
    }"

# ============================================
# 完成
# ============================================
log_info "部署完成!"
log_info "验证步骤:"
echo "  1. tcb fn log device-auth -e $ENV_ID --tail"
echo "  2. curl -X POST https://$ENV_ID.api.tcloudbasegateway.com/api/v1/devices/challenge"
echo "  3. tcb env use $ENV_ID && tcb fn invoke device-auth --params '...'"
