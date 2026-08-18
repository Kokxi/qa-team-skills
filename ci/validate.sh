#!/usr/bin/env bash
# qa-team-skills CI 校验脚本
# 用途：检查技能文件结构完整性、禁止硬编码行业词
# 使用方式：在 qa-team-skills 目录下运行 bash ci/validate.sh
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
ERRORS=()
WARNINGS=()

echo "🔍 qa-team-skills 校验中..."

# ── 1. 基础结构检查 ──────────────────────────────────
check_file() {
  local file="$1"
  if [[ ! -f "$SKILL_DIR/$file" ]]; then
    ERRORS+=("缺少必要文件: $file")
  fi
}

check_file "SKILL.md"
check_file "VERSION"
check_file "skills/qa-prd/SKILL.md"
check_file "skills/qa-case/SKILL.md"
check_file "skills/qa-agent/SKILL.md"
check_file "skills/qa-bug/SKILL.md"
check_file "skills/qa-report/SKILL.md"
check_file "skills/qa-team/SKILL.md"
check_file "skills/qa-explore/SKILL.md"
check_file "docs/user-manual.md"
check_file "templates/requirement.md"
check_file "templates/agent-test.md"
check_file "templates/error-output.md"
check_file "ci/forbidden.txt"
check_file ".gitignore"
check_file "docs/process-integration.md"
check_file "docs/version-policy.md"
check_file "examples/README.md"
check_file "examples/prd-demo.md"
check_file "examples/login-demo.md"
check_file "examples/case-demo.md"
check_file "examples/agent-demo.md"
check_file "examples/bug-demo.md"
check_file "examples/report-demo.md"
check_file "examples/team-demo.md"

# ── 2. SKILL.md 必填字段检查 ──────────────────────────
SKILL_MD="$SKILL_DIR/SKILL.md"
if [[ -f "$SKILL_MD" ]]; then
  for field in "name:" "description:" "Skill 总览" "通用约束" "版本管理" "能力矩阵"; do
    if ! grep -q "$field" "$SKILL_MD"; then
      ERRORS+=("SKILL.md 缺少必填字段: $field")
    fi
  done
fi

# ── 2.5 各 Skill 关键章节检查 ──────────────────────────
for skill_dir in "$SKILL_DIR"/skills/*/; do
  name=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  # 检查防注入声明
  if ! grep -q "防注入声明" "$skill_md"; then
    ERRORS+=("$name/SKILL.md 缺少「防注入声明」章节")
  fi
  # 检查双段式 description（负向排除）
  if ! grep -q "不用于" "$skill_md"; then
    ERRORS+=("$name/SKILL.md 缺少负向排除（何时不用）")
  fi
  # 检查第零步记忆加载
  if ! grep -q "历史加载" "$skill_md"; then
    ERRORS+=("$name/SKILL.md 缺少历史加载流程")
  fi
  # 检查输出前自检
  if ! grep -q "输出前自检" "$skill_md"; then
    ERRORS+=("$name/SKILL.md 缺少「输出前自检」章节")
  fi
done

# ── 3. 禁止硬编码行业词（读取 ci/forbidden.txt） ──
FORBIDDEN_FILE="$SKILL_DIR/ci/forbidden.txt"
if [[ -f "$FORBIDDEN_FILE" ]]; then
  while IFS= read -r word || [[ -n "$word" ]]; do
    [[ -z "$word" || "$word" =~ ^# ]] && continue
    matches=$(grep -rn "$word" "$SKILL_DIR/prompts" "$SKILL_DIR/SKILL.md" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
      ERRORS+=("发现硬编码行业词 '$word' 在 prompt 或 SKILL.md 中: $matches")
    fi
  done < "$FORBIDDEN_FILE"
else
  ERRORS+=("ci/forbidden.txt 文件不存在")
fi

# ── 4. VERSION 文件一致性检查 ──────────────────────────
VERSION_FILE="$SKILL_DIR/VERSION"
if [[ -f "$VERSION_FILE" ]]; then
  FILE_VER=$(cat "$VERSION_FILE" | tr -d '\n\r ')
  META_VER=$(grep "version:" "$SKILL_MD" | head -1 | sed 's/.*version: *//' | tr -d '\n\r ')
  if [[ "$FILE_VER" != "$META_VER" ]]; then
    ERRORS+=("VERSION 文件 ($FILE_VER) 与 SKILL.md ($META_VER) 版本不一致")
  fi
else
  ERRORS+=("VERSION 文件不存在")
fi

# ── 5. 禁止残留旧目录 ─────────────────────────
# 旧 Prompt 目录（prompts/）在 skills/ 迁移完成后删除；删除前提示
if [[ -d "$SKILL_DIR/prompts" ]]; then
  WARNINGS+=("prompts/ 目录仍存在——能力已迁移至 skills/，请确认迁移完整后删除")
fi
OLD_DIRS=("prompts/req-analyze" "prompts/case-gen")
for d in "${OLD_DIRS[@]}"; do
  if [[ -d "$SKILL_DIR/$d" ]]; then
    ERRORS+=("发现旧 Prompt 目录残留: $d，请删除")
  fi
done

# ── 6. 输出结果 ────────────────────────────────────────
echo ""
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo "⚠️  提醒:"
  for w in "${WARNINGS[@]}"; do echo "  - $w"; done
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "❌ 校验失败 (${#ERRORS[@]} 项):"
  for e in "${ERRORS[@]}"; do echo "  - $e"; done
  exit 1
else
  VERSION=$(cat "$VERSION_FILE")
  echo "✅ qa-team-skills $VERSION 校验通过"
  echo "   - 6 个指令 Prompt 完整（含注入防护+自检）"
  echo "   - SKILL.md 字段完整"
  echo "   - 模板文件完整"
  echo "   - 无硬编码行业词"
  echo "   - 无旧目录残留"
  echo "   - 版本号一致"
fi