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
check_file "prompts/prd/prompt.md"
check_file "prompts/case/prompt.md"
check_file "prompts/agent/prompt.md"
check_file "prompts/bug/prompt.md"
check_file "prompts/report/prompt.md"
check_file "prompts/team/prompt.md"
check_file "docs/user-manual.md"
check_file "templates/requirement.md"
check_file "templates/agent-test.md"
check_file "templates/error-output.md"
check_file "ci/forbidden.txt"
check_file "ci/publish.sh"
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
check_file "examples/qa-demo.md"

# ── 2. SKILL.md 必填字段检查 ──────────────────────────
SKILL_MD="$SKILL_DIR/SKILL.md"
if [[ -f "$SKILL_MD" ]]; then
  for field in "name:" "description:" "指令总览" "通用约束"; do
    if ! grep -q "$field" "$SKILL_MD"; then
      ERRORS+=("SKILL.md 缺少必填字段: $field")
    fi
  done
fi

# ── 2.5 各 Prompt 关键章节检查 ──────────────────────────
for prompt_file in "$SKILL_DIR"/prompts/*/prompt.md; do
  name=$(basename "$(dirname "$prompt_file")")
  # 检查注入防护
  if ! grep -q "防注入声明" "$prompt_file"; then
    ERRORS+=("$name/prompt.md 缺少「防注入声明」章节")
  fi
  # 检查输出前自检
  if ! grep -q "输出前自检" "$prompt_file"; then
    ERRORS+=("$name/prompt.md 缺少「输出前自检」章节")
  fi
  # 检查约束（agent 和 case 必须包含黑盒方法/设计方法）
  if [[ "$name" == "case" || "$name" == "agent" ]]; then
    if ! grep -q "设计方法" "$prompt_file"; then
      ERRORS+=("$name/prompt.md 缺少「设计方法」字段（必填）")
    fi
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

# ── 5. 禁止残留旧 Prompt 目录 ─────────────────────────
OLD_DIRS=("prompts/req-analyze" "prompts/case-gen")
for d in "${OLD_DIRS[@]}"; do
  if [[ -d "$SKILL_DIR/$d" ]]; then
    ERRORS+=("发现旧 Prompt 目录残留: $d，请删除")
  fi
done

# ── 5.5 指令清单一致性检查（防新增指令漏同步） ────────────
# 三方指令清单必须一致：
#   ① prompts/ 下的子目录（每个指令一个目录，qa 入口除外）
#   ② run_llm_eval.py 的 CMD_TO_PROMPT 映射
#   ③ SKILL.md 渐进式加载指引表的指令行
declare -A CMD_TO_PROMPT=(
  ["prd"]="/qa-prd" ["case"]="/qa-case" ["agent"]="/qa-agent"
  ["bug"]="/qa-bug" ["report"]="/qa-report" ["team"]="/qa-team"
  ["explore"]="/qa-explore"
)

# ① 从 prompts/ 目录收集指令
PROMPT_DIRS=()
for d in "$SKILL_DIR"/prompts/*/; do
  name=$(basename "$d")
  [[ "$name" == "qa" ]] && continue  # qa 是统一入口，不是子指令
  [[ -f "$d/prompt.md" ]] && PROMPT_DIRS+=("$name")
done

# ② 从 run_llm_eval.py 收集映射
LLM_MAPPED=()
if [[ -f "$SKILL_DIR/ci/run_llm_eval.py" ]]; then
  while read -r key; do
    [[ -n "$key" ]] && LLM_MAPPED+=("$key")
  done < <(grep -oP '"/qa-[a-z]+"\s*:\s*"[a-z]+"' "$SKILL_DIR/ci/run_llm_eval.py" | sed -E 's/.*: *"([a-z]+)"/\1/')
fi

# ③ 从 SKILL.md 渐进式加载指引收集指令
SKILL_CMDS=()
while read -r key; do
  [[ -n "$key" ]] && SKILL_CMDS+=("$key")
done < <(grep -oP 'prompts/[a-z]+/prompt\.md' "$SKILL_MD" | sed -E 's|prompts/([a-z]+)/prompt\.md|\1|' | grep -v '^qa$')

# 比对 ① 目录 与 ② 映射 与 ③ SKILL.md
for name in "${PROMPT_DIRS[@]}"; do
  if [[ -z "${CMD_TO_PROMPT[$name]:-}" ]]; then
    ERRORS+=("指令目录 prompts/$name/ 未在 validate.sh 指令清单中登记（新增指令需在 CMD_TO_PROMPT 补充）")
  fi
  if [[ -z "$(printf '%s\n' "${LLM_MAPPED[@]}" | grep -qx "$name" && echo yes)" ]]; then
    ERRORS+=("指令目录 prompts/$name/ 未在 ci/run_llm_eval.py CMD_TO_PROMPT 中登记（LLM 评测会漏测此指令）")
  fi
  if [[ -z "$(printf '%s\n' "${SKILL_CMDS[@]}" | grep -qx "$name" && echo yes)" ]]; then
    ERRORS+=("指令目录 prompts/$name/ 未在 SKILL.md 渐进式加载指引表中列出（AI 无法按需加载）")
  fi
done

# 反向检查：映射/指引表中有、目录中无 → 悬空引用
for name in "${LLM_MAPPED[@]}" "${SKILL_CMDS[@]}"; do
  if [[ ! -d "$SKILL_DIR/prompts/$name" ]]; then
    ERRORS+=("指令 $name 被 run_llm_eval.py 或 SKILL.md 引用，但 prompts/$name/ 目录不存在（悬空引用）")
  fi
done

# ── 5.6 文档交叉引用一致性检查（防 SKILL.md 章节被误删后悬空引用） ──
# README / user-manual 中引用的 SKILL.md 章节（「xxx」或结构图注释 + xxx）
# 必须在 SKILL.md 中存在对应 "# xxx" 标题，否则报错。
# 背景：v1.6.3 精简 SKILL.md 时误删「人工校验规则」章节，
#       README 两处引用变为悬空引用，且无检查拦截——本节防止同类问题。
# ① 章节引用检查：只检查"明确指向 SKILL.md 的上下文"中的「xxx」词
#    方法：先筛出含 "SKILL.md" 的行，再从中提取「」内的词
#    避免把普通概念名词（如「业务分层」「使用」）误当章节引用
DOC_REFS=$(grep -E 'SKILL\.md' "$SKILL_DIR/README.md" "$SKILL_DIR/docs/user-manual.md" 2>/dev/null \
  | grep -oP '「[^」]+」' | sed 's/「\(.*\)」/\1/' | sort -u)
for sec in $DOC_REFS; do
  if ! grep -qE "^# $sec" "$SKILL_MD" 2>/dev/null; then
    ERRORS+=("文档引用了 SKILL.md 不存在的章节: 「$sec」（README/user-manual 悬空引用）")
  fi
done
# ② 结构图注释引用：README/user-manual 的项目结构图里 SKILL.md 行
#    提到的章节名（如"技能入口：8 指令总览 + 人工校验规则"）必须存在于 SKILL.md
KNOWN_SECTIONS=("指令总览" "指令路由边界" "角色限定" "通用约束" "常见陷阱" "指令详情" "人工校验规则" "记忆模块")
for sec in "${KNOWN_SECTIONS[@]}"; do
  # 结构图行提到该章节名（格式：SKILL.md # ... + 章节名 或 SKILL.md # ... + 章节名）
  if grep -E 'SKILL\.md' "$SKILL_DIR/README.md" "$SKILL_DIR/docs/user-manual.md" 2>/dev/null | grep -q "$sec"; then
    if ! grep -qE "^# $sec" "$SKILL_MD" 2>/dev/null; then
      ERRORS+=("结构图注释引用了 SKILL.md 不存在的章节: $sec（README/user-manual 悬空引用）")
    fi
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
  echo "   - 8 个指令 Prompt 完整（含注入防护+自检）"
  echo "   - 指令清单三方一致（prompts/ ↔ run_llm_eval.py ↔ SKILL.md）"
  echo "   - SKILL.md 字段完整"
  echo "   - 模板文件完整"
  echo "   - 无硬编码行业词"
  echo "   - 无旧目录残留"
  echo "   - 版本号一致"
  echo "   - 发布脚本完整（ci/publish.sh）"
  echo "   - 文档章节引用一致（README/user-manual ↔ SKILL.md）"
fi