#!/usr/bin/env bash
# qa-team-skills 发布脚本
# 用途：一键发布到 GitHub + ClawHub + skillhub.cn（版本号从 VERSION 文件自动读取）
# 使用方式：在 qa-team-skills 目录下运行 bash ci/publish.sh [--dry-run] [--github-only]
#
# 发布链路：
#   1. 前置校验：跑 ci/validate.sh + ci/run-evals.sh，全过才允许发布
#   2. GitHub：git push origin main（当前分支必须是 main）
#   3. ClawHub：clawhub publish（clawhub CLI，需已登录）
#   4. skillhub.cn：用 Python CLI（~/.skillhub/skills_store_cli.py，需已登录）
#      - 注意：skillhub.cn 服务端有文件白名单，会拒绝 .clawhubignore/.gitignore/LICENSE/VERSION，
#        因此先复制到临时目录并剔除这些文件再发布
#
# 参数：
#   --dry-run      只做前置校验 + 生成临时发布目录，不真正发布（skillhub 走 --dry-run）
#   --github-only  只推 GitHub，跳过 ClawHub / skillhub.cn
#   --skip-checks  跳过前置校验（紧急修复时用）
set -uo pipefail

# Windows + Git Bash：强制 Python 以 UTF-8 输出（GBK 会抛 UnicodeEncodeError）
export PYTHONIOENCODING=utf-8
export LC_ALL=C.UTF-8

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
VERSION=$(cat "$SKILL_DIR/VERSION" | tr -d '\n\r ')
VERSION=${VERSION#v}   # VERSION 文件含 v 前缀，发布平台用裸版本号

DRY_RUN=0
GITHUB_ONLY=0
SKIP_CHECKS=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --github-only) GITHUB_ONLY=1 ;;
    --skip-checks) SKIP_CHECKS=1 ;;
  esac
done

echo "🚀 qa-team-skills v$VERSION 发布"
echo "================================================"

# ── 1. 前置校验 ──────────────────────────────────────
if [[ $SKIP_CHECKS -eq 0 ]]; then
  echo ""
  echo "▶ 1. 前置校验"
  if ! bash "$SCRIPT_DIR/validate.sh"; then
    echo "❌ validate.sh 未通过，中止发布（如需强制发布加 --skip-checks）"
    exit 1
  fi
  if ! bash "$SCRIPT_DIR/run-evals.sh"; then
    echo "❌ run-evals.sh 未通过，中止发布（如需强制发布加 --skip-checks）"
    exit 1
  fi
else
  echo ""
  echo "▶ 1. 前置校验（--skip-checks 已跳过）"
fi

# ── 2. GitHub 推送 ───────────────────────────────────
echo ""
echo "▶ 2. GitHub 推送"
BRANCH=$(git -C "$SKILL_DIR" branch --show-current)
if [[ "$BRANCH" != "main" ]]; then
  echo "⚠️  当前分支 $BRANCH 不是 main，跳过 GitHub 推送（请先在 main 上合并再发布）"
elif [[ $DRY_RUN -eq 1 ]]; then
  echo "  [dry-run] 将推送 origin main"
else
  git -C "$SKILL_DIR" push origin main && echo "  ✔ 已推送 origin main"
fi

# ── 3. ClawHub 发布 ──────────────────────────────────
if [[ $GITHUB_ONLY -eq 1 ]]; then
  echo ""
  echo "▶ 3/4. ClawHub + skillhub.cn（--github-only 已跳过）"
else
  if command -v clawhub >/dev/null 2>&1; then
    echo ""
    echo "▶ 3. ClawHub 发布"
    CHANGELOG="v${VERSION}: $(grep -A2 "^## v${VERSION}" "$SKILL_DIR/docs/CHANGELOG.md" | head -1 | sed 's/^## //' | sed 's/(.*)//' | xargs)"
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  [dry-run] clawhub publish $SKILL_DIR --version $VERSION"
    else
      if clawhub publish "$SKILL_DIR" --version "$VERSION" --changelog "$CHANGELOG"; then
        echo "  ✔ ClawHub 已发布 qa-team-skills@$VERSION"
      else
        echo "  ⚠️  ClawHub 发布失败（请检查 clawhub whoami 登录状态）"
      fi
    fi
  else
    echo ""
    echo "▶ 3. ClawHub 发布"
    echo "  ⚠️  未找到 clawhub CLI（npm i -g clawhub），跳过"
  fi

  # ── 4. skillhub.cn 发布 ──────────────────────────────
  echo ""
  echo "▶ 4. skillhub.cn 发布"
  SKILLHUB_CLI="$HOME/.skillhub/skills_store_cli.py"
  if [[ ! -f "$SKILLHUB_CLI" ]]; then
    echo "  ⚠️  未找到 $SKILLHUB_CLI，跳过（skillhub.cn 官方 CLI 未安装）"
  else
    # 4.1 生成临时发布目录（剔除 skillhub.cn 白名单拒绝的文件）
    TMP_PUB=$(mktemp -d "${TMPDIR:-/tmp}/qa-team-skills-pub-${VERSION}-XXXXXX")
    cp -a "$SKILL_DIR/." "$TMP_PUB/"
    rm -rf "$TMP_PUB/.git" "$TMP_PUB/.omo" "$TMP_PUB/.claude" "$TMP_PUB/.idea"
    rm -f "$TMP_PUB/.clawhubignore" "$TMP_PUB/.gitignore" "$TMP_PUB/LICENSE" "$TMP_PUB/VERSION"

    echo "  临时发布目录: $TMP_PUB（已剔除 .clawhubignore/.gitignore/LICENSE/VERSION）"
    CHANGELOG="v${VERSION}: $(grep -A2 "^## v${VERSION}" "$SKILL_DIR/docs/CHANGELOG.md" | head -1 | sed 's/^## //' | sed 's/(.*)//' | xargs)"
    if [[ $DRY_RUN -eq 1 ]]; then
      python "$SKILLHUB_CLI" --skip-self-upgrade publish "$TMP_PUB" \
        --version "$VERSION" --changelog "$CHANGELOG" --dry-run
      echo "  [dry-run] 临时目录保留: $TMP_PUB"
    else
      if python "$SKILLHUB_CLI" --skip-self-upgrade publish "$TMP_PUB" \
        --version "$VERSION" --changelog "$CHANGELOG"; then
        echo "  ✔ skillhub.cn 已发布 qa-team-skills@$VERSION"
      else
        echo "  ⚠️  skillhub.cn 发布失败（请检查登录状态或服务端白名单）"
      fi
      rm -rf "$TMP_PUB"
    fi
  fi
fi

echo ""
echo "================================================"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "✅ dry-run 完成（未执行任何实际发布）"
else
  echo "✅ 发布流程执行完毕"
fi