#!/usr/bin/env bash
# qa-team-skills 评测 runner
# 用途：跑触发评测集（规则路由基线）+ 功能评测集（prompt↔eval 契约断言）
# 使用方式：在 qa-team-skills 目录下运行 bash ci/run-evals.sh
# 说明：本 skill 是纯 Prompt 形态无 HTTP API，runner 只做两类可落地检查：
#   1) 触发评测：用 intent-rules.md 的关键词规则做路由，算准确率作为 LLM 路由的基线对照
#      （LLM 路由准确率应 ≥ 此规则基线才算合格）
#   2) 契约断言：把 functional-eval.json 的 assertion 翻译成对 prompt 文件的静态检查，
#      捕获 "prompt 定义与 eval 期望" 不一致（如标题写 10 个维度但 eval 要 11 个）
#   真正调 LLM 的端到端评测留 --llm 接口位，接 API 后启用
set -uo pipefail

# Windows + Git Bash：强制 Python 以 UTF-8 输出，否则默认 GBK 编码会导致
# 触发评测文件里的中文 query 乱码、emoji 打印抛 UnicodeEncodeError（预存 bug）
export PYTHONIOENCODING=utf-8
export LC_ALL=C.UTF-8

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
VERSION=$(cat "$SKILL_DIR/VERSION" | tr -d '\n\r ')
# VERSION 文件本身含 v 前缀（如 v1.5.0），去掉避免重复
VERSION=${VERSION#v}
REPORT_DIR="$SKILL_DIR/evals/history"
REPORT_FILE="$REPORT_DIR/report-${VERSION}-$(date +%Y%m%d-%H%M%S).json"

mkdir -p "$REPORT_DIR"

PASS=0
FAIL=0
FAILS=()
note() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); FAILS+=("$1"); }

echo "🧪 qa-team-skills v$VERSION 评测 runner"
echo "================================================"

# ── 1. 触发评测：规则路由基线 ──────────────────────
# 基于 intent-rules.md 的关键词表做规则路由，对照 trigger-eval.json 的期望
# 注意：这是"规则基线"，目的是给 LLM 路由准确率一个对照下限
route_by_rule() {
  local q="$1"
  # 统一去 CRLF，避免 Windows 换行污染比较
  q=$(printf '%s' "$q" | tr -d '\r\n')
  # 反例关键词优先：含这些则不触发（注意"能不能"在准出语境是正例，不放入反例）
  if echo "$q" | grep -qE '什么是|什么叫|解释一下|区别|可以吗|帮我写(一个|个) (python|脚本|代码)|搭一套|连接失败|转成|转成 CSV|CAP theorem'; then
    echo "none"; return
  fi
  # 探索性测试：含探索类关键词优先于其他分支（"自由探索""发现未知问题"口语化表述也覆盖）
  if echo "$q" | grep -qE '探索性测试|探索测试|自由探索|发现未知问题|随便测测'; then echo "/qa-explore"; return; fi
  # 准出/发版评估优先匹配到 team（"能不能发""能不能按期发布""发版评估"）
  if echo "$q" | grep -qE '能不能发|能不能.*发|能不能.*发布|能不能按期|发版.*评估|检查下能不能|准出'; then echo "/qa-team"; return; fi
  # 正例路由（按 intent-rules.md 顺序，多匹配时取最具体）
  if echo "$q" | grep -qE '评审|分析.*(需求|PRD)|review.*需求|需求.*遗漏|需求.*看下|需求.*理解|看下这个需求|看下.*需求|PRD.*看|需求.*完整不完整'; then echo "/qa-prd"; return; fi
  if echo "$q" | grep -qE '设计.*用例|出.*用例|测.*幻觉|测.*Agent|测.*智能|测.*AI.*(客服|助手)|Agent.*安全|智能客服'; then
    if echo "$q" | grep -qE '幻觉|Agent|智能客服|AI 客服|AI 助手'; then echo "/qa-agent"; return; fi
    echo "/qa-case"; return
  fi
  # report 的"数据整理/统计展示"优先于 bug（"整理缺陷数据/哪个模块问题最多"偏统计非根因）
  if echo "$q" | grep -qE '整理.*数据|哪个模块.*最多|统计|日报|周报|阶段报告|季度|写成.*报|出份.*报|报告'; then
    if echo "$q" | grep -qE '整理.*数据|哪个模块.*最多|统计'; then echo "/qa-report"; return; fi
    if echo "$q" | grep -qE '能不能发|发版|能不能.*发布|准出|能不能按期'; then echo "/qa-team"; return; fi
    echo "/qa-report"; return
  fi
  if echo "$q" | grep -qE 'Bug|缺陷|报.*问题|漏测|没反应|对不上|没发现|复盘.*为什么|出了个事故|不知道怎么描述'; then
    # "复盘" 在团队管理语境
    if echo "$q" | grep -qE '复盘|漏测|防以后|线上.*事故|为什么测试.*没发现'; then echo "/qa-team"; return; fi
    echo "/qa-bug"; return
  fi
  if echo "$q" | grep -qE '团队|进度|效能|培训|新人|质量.*评估|质量.*几分|质量.*行不行|看板|加班|产出|能不能发|质量怎么样'; then echo "/qa-team"; return; fi
  echo "none"
}

echo ""
echo "▶ 1. 触发评测（规则路由基线）"
TRIGGER_FILE="$SKILL_DIR/evals/trigger-eval.json"
if [[ ! -f "$TRIGGER_FILE" ]]; then
  fail "trigger-eval.json 不存在"
else
  # 选可用的 python（Windows 上 python3 常是 Store 占位符，优先用 python）
  PY=python
  if ! command -v $PY >/dev/null 2>&1; then PY=python3; fi
  # 用 python 解析 JSON：直接输出"query<TAB>期望路由<TAB>split"（反例期望统一输出 none），bash 只做字符串比较
  $PY - "$TRIGGER_FILE" <<'PYEOF' > /tmp/qa_trigger_result.txt
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    data = json.load(f)
# 兼容两种结构：老版裸数组 vs 新版 {skill_name, version, evals:[...]}
evals = data.get("evals", data) if isinstance(data, dict) else data
for item in evals:
    q = item.get('query','')
    expected = item.get('expected_command')
    should = item.get('should_trigger', True)
    split = item.get('split', 'train')  # train / validation；缺省按 train
    # 反例（不应触发）期望统一为 none；正例期望取 expected_command
    want = 'none' if not should else (expected if expected else 'none')
    print(f"{q}\t{want}\t{split}")
PYEOF
  TRIG_TOTAL=0; TRIG_PASS=0; TRIG_FAIL_LIST=""
  TRAIN_TOTAL=0; TRAIN_PASS=0; VAL_TOTAL=0; VAL_PASS=0
  while IFS=$'\t' read -r q want split; do
    [[ -z "$q" ]] && continue
    # 去 CRLF，避免 Windows 换行导致字符串比较失败
    q=$(printf '%s' "$q" | tr -d '\r\n')
    want=$(printf '%s' "$want" | tr -d '\r\n')
    split=$(printf '%s' "$split" | tr -d '\r\n')
    TRIG_TOTAL=$((TRIG_TOTAL+1))
    got=$(route_by_rule "$q")
    got=$(printf '%s' "$got" | tr -d '\r\n')
    if [[ "$got" == "$want" ]]; then
      TRIG_PASS=$((TRIG_PASS+1))
      if [[ "$split" == "validation" ]]; then VAL_PASS=$((VAL_PASS+1)); else TRAIN_PASS=$((TRAIN_PASS+1)); fi
    else
      TRIG_FAIL_LIST="${TRIG_FAIL_LIST}\n    ✗ [$q] 期望=$want 实际=$got"
    fi
    if [[ "$split" == "validation" ]]; then VAL_TOTAL=$((VAL_TOTAL+1)); else TRAIN_TOTAL=$((TRAIN_TOTAL+1)); fi
  done < /tmp/qa_trigger_result.txt
  TRIG_ACC=$(python -c "print(f'{$TRIG_PASS/$TRIG_TOTAL*100:.1f}' if $TRIG_TOTAL else '0')" 2>/dev/null || python3 -c "print(f'{$TRIG_PASS/$TRIG_TOTAL*100:.1f}' if $TRIG_TOTAL else '0')" 2>/dev/null || echo "0")
  TRAIN_ACC=$(python -c "print(f'{$TRAIN_PASS/$TRAIN_TOTAL*100:.1f}' if $TRAIN_TOTAL else '0')" 2>/dev/null || python3 -c "print(f'{$TRAIN_PASS/$TRAIN_TOTAL*100:.1f}' if $TRAIN_TOTAL else '0')" 2>/dev/null || echo "0")
  VAL_ACC=$(python -c "print(f'{$VAL_PASS/$VAL_TOTAL*100:.1f}' if $VAL_TOTAL else '0')" 2>/dev/null || python3 -c "print(f'{$VAL_PASS/$VAL_TOTAL*100:.1f}' if $VAL_TOTAL else '0')" 2>/dev/null || echo "0")
  echo "  触发准确率: $TRIG_PASS/$TRIG_TOTAL = ${TRIG_ACC}%"
  echo "     ├─ train 集: $TRAIN_PASS/$TRAIN_TOTAL = ${TRAIN_ACC}%（描述优化用）"
  echo "     └─ validation 集: $VAL_PASS/$VAL_TOTAL = ${VAL_ACC}%（防过拟合检验）"
  if [[ -n "$TRIG_FAIL_LIST" ]]; then echo -e "  失败明细:$TRIG_FAIL_LIST"; fi
  # 准确率 < 80% 记为失败（规则基线过低说明 intent-rules 关键词表有缺口）
  if (( $(echo "$TRIG_ACC < 80" | bc -l 2>/dev/null || echo 0) )); then
    fail "触发准确率 ${TRIG_ACC}% < 80% 基线"
  else
    note "触发评测准确率 ${TRIG_ACC}% ≥ 80%"
  fi
fi

# ── 2. 契约断言：functional-eval.json ↔ prompt 文件 ──────────────────────
echo ""
echo "▶ 2. 功能评测（prompt↔eval 契约断言）"
PROMPT_DIR="$SKILL_DIR/prompts"
check_contains() { # file pattern  desc
  if grep -qE "$2" "$1" 2>/dev/null; then note "$3 ✔"; else fail "$3 ✗ ($1 未匹配 $2)"; fi
}
check_count() { # file pattern expected_count desc
  local got
  got=$(grep -cE "$2" "$1" 2>/dev/null || echo 0)
  if [[ "$got" -ge "$3" ]]; then note "$4 ✔ (实际 $got ≥ $3)"; else fail "$4 ✗ ($1 仅 $got < $3)"; fi
}

# /qa-prd 契约：11 维度 + 业务分层 + 澄清 + 严重程度 + 无评审结论
PRD="$PROMPT_DIR/prd/prompt.md"
check_count "$PRD" '^\| [0-9]+ \|' 11 "prd 定义了 11 个评审维度行"
check_contains "$PRD" '业务分层' "prd 含业务分层建议"
check_contains "$PRD" '澄清|需澄清' "prd 含澄清问题清单"
check_contains "$PRD" '严重程度|高.*中.*低' "prd 含严重程度分级"
# P004：不应包含评审结论（"建议通过/不通过""评审结论：通过"等实际给出结论才算违规；
# 纯否定句如"不做评审结论""不由 AI 判断"是正确表述，不算违规）
if grep -qE '建议(通过|不通过)|评审结论[：:]\s*(通过|不通过)|同意(通过|不通过)' "$PRD" 2>/dev/null; then
  fail "prd 含评审结论（违反 P004）"
else
  note "prd 不含评审结论 ✔"
fi

# /qa-case 契约：6 类型 + 业务分层 + 设计方法 + 动词开头
CASE="$PROMPT_DIR/case/prompt.md"
check_contains "$CASE" '功能/边界/异常/安全/性能/兼容性' "case 列出 6 种测试类型"
check_contains "$CASE" '核心层.*体验层.*增值层|业务分层' "case 含业务分层"
check_contains "$CASE" '设计方法.*必填|必填.*设计方法' "case 标注设计方法必填"
check_contains "$CASE" '动词|可执行的动词' "case 要求步骤动词开头"
check_contains "$CASE" '信息泄露|错误提示.*通用化' "case 含信息泄露防护检查"

# /qa-bug 契约：质量评估 + 根因 + 置信度 + 修复建议 + 回归要点
BUG="$PROMPT_DIR/bug/prompt.md"
check_contains "$BUG" '质量评估|达标' "bug 含质量评估"
check_contains "$BUG" '根因分析|根因分类' "bug 含根因分析"
check_contains "$BUG" '置信度' "bug 标注置信度"
check_contains "$BUG" '修复建议|修复方向' "bug 含修复建议"
check_contains "$BUG" '回归' "bug 含回归测试要点"

# /qa-report 契约：报告类型 + 简明摘要 + 来源标注
REPORT="$PROMPT_DIR/report/prompt.md"
check_contains "$REPORT" '日报|周报|阶段|季度|专项' "report 列出报告类型"
check_contains "$REPORT" '简明摘要|30 秒速览|30秒速览' "report 含简明摘要"
check_contains "$REPORT" '来源标注|数据来源' "report 要求来源标注"

# /qa-team 契约：子能力 + 进度表格 + 风险标注 + 简明摘要
TEAM="$PROMPT_DIR/team/prompt.md"
check_contains "$TEAM" '进度看板|进度.*表格|子能力' "team 含子能力路由"
check_contains "$TEAM" '风险|延期|延期风险' "team 含风险标注"
check_contains "$TEAM" '简明摘要|简明' "team 含简明摘要"

# /qa-agent 契约：16 维度 + 设计方法必填 + RAG 维度
AGENT="$PROMPT_DIR/agent/prompt.md"
check_contains "$AGENT" '16 个维度|16维度' "agent 定义 16 个维度"
check_contains "$AGENT" '设计方法.*必填|必填.*设计方法' "agent 设计方法必填"
check_contains "$AGENT" 'RAG' "agent 含 RAG 维度"
# 维度名一致性：维度表（10-13）与覆盖确认清单必须同名，禁止残留旧维度名
if grep -qE '长文本|多语言|正则合规|防御性|13维度' "$AGENT" 2>/dev/null; then
  fail "agent 残留旧维度名（长文本/多语言/正则合规/防御性/13维度），与维度表不一致"
else
  note "agent 维度名一致（无旧名残留） ✔"
fi
if grep -qE '10-AI稳定性.*11-可控性.*12-资源消耗.*13-合规与伦理' "$AGENT" 2>/dev/null; then
  note "agent 覆盖确认清单维度名与维度表一致 ✔"
else
  fail "agent 覆盖确认清单缺少新维度名（10-AI稳定性/11-可控性/12-资源消耗/13-合规与伦理）"
fi

# /qa-explore 契约：探索任务卡 + 时间盒 + 起点不超过3
EXPLORE="$PROMPT_DIR/explore/prompt.md"
check_contains "$EXPLORE" '探索任务|任务卡' "explore 含探索任务卡"
check_contains "$EXPLORE" '时间盒' "explore 含时间盒"
check_contains "$EXPLORE" '3 个|不超过 3|不超过3' "explore 限制起点不超过3"

# /qa 入口契约：意图解析（single/multi/auto）+ 任务编排 + 记忆
QA="$PROMPT_DIR/qa/prompt.md"
check_contains "$QA" '意图解析|single|multi' "qa 含意图解析"
check_contains "$QA" '任务编排|执行计划' "qa 含任务编排"
check_contains "$QA" 'auto|自动规划' "qa 含自动规划（v1.5）"

# validation-rules.md 完整性：全部指令的规则表都存在（含 E001 explore）
VAL="$PROMPT_DIR/qa/validation-rules.md"
for rule in 'P001' 'C001' 'B001' 'R001' 'T001' 'A001' 'E001'; do
  check_contains "$VAL" "$rule" "validation-rules 含规则 $rule"
done

# ── 3. 输出结果 + 归档报告 ──────────────────────
echo ""
echo "================================================"
echo "通过: $PASS  失败: $FAIL"
if [[ ${#FAILS[@]} -gt 0 ]]; then
  echo ""
  echo "❌ 失败项:"
  for f in "${FAILS[@]}"; do echo "  - $f"; done
fi

# 写归档报告（JSON）
PY=python; command -v $PY >/dev/null 2>&1 || PY=python3
$PY - "$REPORT_FILE" "$VERSION" "$PASS" "$FAIL" "$TRIG_ACC" "$TRIG_PASS" "$TRIG_TOTAL" "$TRAIN_ACC" "$TRAIN_PASS" "$TRAIN_TOTAL" "$VAL_ACC" "$VAL_PASS" "$VAL_TOTAL" <<'PYEOF' "${FAILS[@]}"
import json, sys
path, ver, p, f, acc, tp, tt, tr_acc, tr_p, tr_t, va_acc, va_p, va_t = sys.argv[1:14]
fails = sys.argv[14:] if len(sys.argv) > 14 else []
report = {
  "version": ver,
  "timestamp": __import__('datetime').datetime.now().isoformat(),
  "summary": {"pass": int(p), "fail": int(f)},
  "trigger_eval": {
    "accuracy": acc + "%", "pass": int(tp), "total": int(tt),
    "train": {"accuracy": tr_acc + "%", "pass": int(tr_p), "total": int(tr_t)},
    "validation": {"accuracy": va_acc + "%", "pass": int(va_p), "total": int(va_t)},
  },
  "failures": list(fails)
}
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(report, fh, ensure_ascii=False, indent=2)
print(f"📋 报告已归档: {path}")
PYEOF

[[ $FAIL -eq 0 ]] && echo "✅ 评测全部通过" || echo "⚠️  有 $FAIL 项失败，请检查"
exit $FAIL
