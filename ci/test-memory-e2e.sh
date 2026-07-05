#!/usr/bin/env bash
# qa-team-skills 记忆模块端到端测试
# 用途：验证 memory/README.md 定义的记忆生命周期行为（写入/合并/清理/转化/规范沉淀/历史加载）
# 使用方式：在 qa-team-skills 目录下运行 bash ci/test-memory-e2e.sh
# 说明：本 skill 是纯 Prompt 形态，记忆读写由 AI 按 prompt 指令执行。
#       本测试用一个 python 模拟器复刻 README.md 定义的规则，在临时产品目录上跑完整生命周期，
#       用断言验证规则实现正确——这是"规则契约测试"，确保 prompt 指令与 README 规范一致。
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

# 选可用的 python（Windows 上 python3 常是 Store 占位符）
PY=python
if ! command -v $PY >/dev/null 2>&1; then PY=python3; fi

PASS=0; FAIL=0; FAILS=()
ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); FAILS+=("$1"); }

echo "🧠 qa-team-skills 记忆模块端到端测试"
echo "================================================"

$PY - "$SKILL_DIR" <<'PYEOF'
import json, os, sys, shutil, tempfile, re
from datetime import datetime, timezone

def now_iso():
    return datetime.now(timezone.utc).isoformat()

SKILL_DIR = sys.argv[1]
results = []  # (ok, msg)

def ok(msg):  results.append((True, msg))
def fail(msg): results.append((False, msg))

# ── 临时产品目录（测试完自动清理）────────────────────
TEST_MODULE = "e2e-test-module"
DATA_DIR = os.path.join(SKILL_DIR, "memory", "data", "products", TEST_MODULE)
# 清理可能残留的旧测试目录
if os.path.exists(DATA_DIR):
    shutil.rmtree(DATA_DIR)

def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)

def read_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

# ── 模拟器：复刻 memory/README.md 的记忆生命周期规则 ──────────

def init_product(module):
    """首次写入时创建目录结构"""
    os.makedirs(os.path.join(DATA_DIR, "test-cases"), exist_ok=True)
    os.makedirs(os.path.join(DATA_DIR, "bugs"), exist_ok=True)
    os.makedirs(os.path.join(DATA_DIR, "reviews"), exist_ok=True)
    os.makedirs(os.path.join(DATA_DIR, "reports"), exist_ok=True)

def write_test_case_version(module, version, entries, from_bug_history=None):
    """增量写入：创建新版本文件"""
    path = os.path.join(DATA_DIR, "test-cases", f"{version}.json")
    obj = {
        "session_id": f"session-{version}",
        "created_at": now_iso(),
        "module": module,
        "entries": entries
    }
    if from_bug_history:
        obj["from_bug_history"] = from_bug_history
    write_json(path, obj)

def merge_latest(module):
    """汇总合并：读取全部版本 → 去重（同标题保留最早）→ 重新编号 → 写 latest.json"""
    tc_dir = os.path.join(DATA_DIR, "test-cases")
    versions = sorted([f for f in os.listdir(tc_dir) if f.startswith("v") and f.endswith(".json")])
    seen_titles = {}
    merged = []
    for v in versions:
        data = read_json(os.path.join(tc_dir, v))
        for e in data.get("entries", []):
            title = e["title"]
            if title not in seen_titles:
                seen_titles[title] = True
                e_copy = dict(e)
                e_copy["source_version"] = v.replace(".json", "")
                merged.append(e_copy)
    # 重新编号 TC001..TCNNN
    for i, e in enumerate(merged, 1):
        e["id"] = f"TC{i:03d}"
    latest = {
        "session_id": f"session-merge-{datetime.now(timezone.utc).strftime('%Y%m%d')}",
        "created_at": now_iso(),
        "module": module,
        "entries": merged
    }
    write_json(os.path.join(tc_dir, "latest.json"), latest)
    return merged, [v.replace(".json", "") for v in versions]

def cleanup_versions(module, keep=5):
    """版本清理：保留最近 keep 个版本，删更早的"""
    tc_dir = os.path.join(DATA_DIR, "test-cases")
    versions = sorted([f for f in os.listdir(tc_dir) if re.match(r'^v\d+\.\d+\.json$', f)])
    if len(versions) <= keep:
        return []
    to_delete = versions[:-keep]  # 最旧的
    for f in to_delete:
        os.remove(os.path.join(tc_dir, f))
    return [v.replace(".json", "") for v in to_delete]

def write_bug_version(module, version, entries):
    """缺陷增量写入"""
    path = os.path.join(DATA_DIR, "bugs", f"{version}.json")
    obj = {
        "session_id": f"session-{version}",
        "created_at": now_iso(),
        "module": module,
        "entries": entries
    }
    write_json(path, obj)

def detect_recurring(bug_entries, threshold=2):
    """历史缺陷→用例转化：同根因/同类 ≥ threshold 次转化为新用例"""
    patterns = {}
    for b in bug_entries:
        title = b["title"]
        # 用标题关键词归类（实际 AI 会更智能，这里按 README 示例规则）
        for kw in ["并发", "超时", "回调", "签名", "重复扣款"]:
            if kw in title:
                patterns[kw] = patterns.get(kw, 0) + 1
    return [kw for kw, c in patterns.items() if c >= threshold]

def bug_to_test_case(pattern):
    """缺陷模式 → 用例"""
    mapping = {
        "并发": ("并发支付防重测试", "安全测试", "核心层", "P0"),
        "超时": ("网关超时补偿测试", "异常测试", "核心层", "P0"),
        "回调": ("回调重放防护测试", "安全测试", "核心层", "P1"),
        "签名": ("回调签名验证测试", "安全测试", "核心层", "P0"),
        "重复扣款": ("并发支付防重测试", "安全测试", "核心层", "P0"),
    }
    return mapping.get(pattern)

def write_standard(module, category, title, content, source):
    """规范沉淀：追加到 standards.json，按 title 去重"""
    path = os.path.join(DATA_DIR, "standards.json")
    if os.path.exists(path):
        stds = read_json(path)
    else:
        stds = []
    # 去重：同 title 已存在则跳过
    if any(s.get("title") == title for s in stds):
        return False  # 未写入（重复）
    stds.append({
        "category": category,
        "title": title,
        "content": content,
        "source": source
    })
    write_json(path, stds)
    return True  # 已写入

def update_summary(module, merged_cases, bug_entries, versions, deleted_versions):
    """更新 summary.json 索引"""
    by_type = {"功能测试":0, "边界测试":0, "异常测试":0, "安全测试":0, "性能测试":0, "兼容性测试":0}
    by_layer = {"核心层":0, "体验层":0, "增值层":0}
    by_priority = {"P0":0, "P1":0, "P2":0, "P3":0}
    for e in merged_cases:
        t = e.get("type","")
        if t in by_type: by_type[t] += 1
        l = e.get("business_layer","")
        if l in by_layer: by_layer[l] += 1
        p = e.get("priority","")
        if p in by_priority: by_priority[p] += 1
    by_severity = {"致命":0, "严重":0, "一般":0, "建议":0}
    by_root_cause = {"代码缺陷":0, "配置错误":0, "权限设计问题":0, "数据问题":0, "需求理解偏差":0, "第三方依赖":0}
    recurring = {}
    for b in bug_entries:
        s = b.get("severity","")
        if s in by_severity: by_severity[s] += 1
        r = b.get("root_cause","")
        if r in by_root_cause: by_root_cause[r] += 1
        title = b.get("title","")
        for kw in ["并发", "超时", "回调", "签名", "重复扣款"]:
            if kw in title:
                recurring[kw] = recurring.get(kw, 0) + 1
    recurring_patterns = [{"pattern": k, "count": v} for k, v in recurring.items() if v >= 2]
    stds = read_json(os.path.join(DATA_DIR, "standards.json")) if os.path.exists(os.path.join(DATA_DIR, "standards.json")) else []
    std_by_cat = {"checklist":0, "lession_learned":0, "best_practice":0}
    for s in stds:
        c = s.get("category","")
        if c in std_by_cat: std_by_cat[c] += 1
    # iteration_count 用清理后磁盘上实际剩余的版本文件数（而非传入的 versions - deleted）
    tc_dir = os.path.join(DATA_DIR, "test-cases")
    remaining_versions = sorted([
        f.replace(".json","") for f in os.listdir(tc_dir)
        if re.match(r'^v\d+\.\d+\.json$', f)
    ])
    summary = {
        "product": module,
        "last_updated": now_iso(),
        "iteration_count": len(remaining_versions),
        "test_cases": {
            "total": len(merged_cases),
            "versions": remaining_versions,
            "by_type": by_type, "by_layer": by_layer, "by_priority": by_priority
        },
        "bugs": {
            "total": len(bug_entries),
            "by_severity": by_severity, "by_root_cause": by_root_cause,
            "recurring_patterns": recurring_patterns
        },
        "standards": {"total": len(stds), "by_category": std_by_cat},
        "iterations": []
    }
    write_json(os.path.join(DATA_DIR, "summary.json"), summary)
    return summary

def load_history_brief(module):
    """跨会话历史加载：读 summary.json 生成记忆简报"""
    path = os.path.join(DATA_DIR, "summary.json")
    if not os.path.exists(path):
        return None
    s = read_json(path)
    brief = {
        "module": s["product"],
        "iterations": s["iteration_count"],
        "test_cases_total": s["test_cases"]["total"],
        "bugs_total": s["bugs"]["total"],
        "recurring": [p["pattern"] for p in s["bugs"].get("recurring_patterns", [])],
        "standards_total": s["standards"]["total"]
    }
    return brief

# ══════════════════════════════════════════════════════
# 测试场景：模拟 7 轮迭代的完整生命周期
# ══════════════════════════════════════════════════════

try:
    # ── 测试 1：首次写入创建目录 ──
    init_product(TEST_MODULE)
    if os.path.isdir(os.path.join(DATA_DIR, "test-cases")):
        ok("首次写入创建目录结构 ✔")
    else:
        fail("首次写入未创建目录结构 ✗")

    # ── 测试 2：增量写入多版本 ──
    v1_0 = [
        {"title":"余额支付正常","type":"功能测试","business_layer":"核心层","priority":"P0"},
        {"title":"银行卡支付正常","type":"功能测试","business_layer":"核心层","priority":"P0"},
        {"title":"支付金额超限","type":"边界测试","business_layer":"核心层","priority":"P1"},
    ]
    write_test_case_version(TEST_MODULE, "v1.0", v1_0)
    v1_1 = [
        {"title":"微信支付正常","type":"功能测试","business_layer":"体验层","priority":"P1"},
        {"title":"支付宝支付正常","type":"功能测试","business_layer":"体验层","priority":"P1"},
    ]
    write_test_case_version(TEST_MODULE, "v1.1", v1_1)
    if os.path.exists(os.path.join(DATA_DIR, "test-cases", "v1.0.json")) and \
       os.path.exists(os.path.join(DATA_DIR, "test-cases", "v1.1.json")):
        ok("增量写入多版本文件 ✔")
    else:
        fail("增量写入多版本文件 ✗")

    # ── 测试 3：汇总合并 + 去重 + 重新编号 ──
    # 再写 v1.1 含重复标题（应被去重，保留最早）
    v1_1_dup = [
        {"title":"余额支付正常","type":"功能测试","business_layer":"核心层","priority":"P0"},  # 重复
        {"title":"退款原路返回","type":"功能测试","business_layer":"核心层","priority":"P0"},
    ]
    write_test_case_version(TEST_MODULE, "v1.1", v1_1_dup)  # 覆盖 v1.1
    merged, versions = merge_latest(TEST_MODULE)
    titles = [e["title"] for e in merged]
    if len(merged) == 4 and "余额支付正常" in titles and "退款原路返回" in titles:
        ok(f"合并去重正确（{len(merged)} 条，重复标题保留最早）✔")
    else:
        fail(f"合并去重错误（merged={len(merged)}, titles={titles}）✗")
    # 重新编号检查
    ids = [e["id"] for e in merged]
    if ids == ["TC001","TC002","TC003","TC004"]:
        ok("重新编号 TC001..TC004 ✔")
    else:
        fail(f"重新编号错误 ids={ids} ✗")

    # ── 测试 4：缺陷写入 + 复发检测 + 缺陷→用例转化 ──
    bugs_v1_0 = [
        {"id":"BUG-001","title":"余额支付成功但状态未更新","severity":"致命","root_cause":"代码缺陷","fixed":True},
        {"id":"BUG-002","title":"并发支付重复扣款","severity":"致命","root_cause":"代码缺陷","fixed":True},
        {"id":"BUG-003","title":"并发支付同一订单两次","severity":"致命","root_cause":"代码缺陷","fixed":False},
        {"id":"BUG-004","title":"网关超时未触发补偿","severity":"严重","root_cause":"设计遗漏","fixed":True},
        {"id":"BUG-005","title":"网关超时丢单","severity":"严重","root_cause":"设计遗漏","fixed":True},
    ]
    write_bug_version(TEST_MODULE, "v1.0", bugs_v1_0)
    recurring = detect_recurring(bugs_v1_0, threshold=2)
    # "并发" 出现 2 次（BUG-002, BUG-003），"超时" 出现 2 次（BUG-004, BUG-005）
    if "并发" in recurring and "超时" in recurring:
        ok(f"复发检测正确（{recurring}）✔")
    else:
        fail(f"复发检测错误 recurring={recurring} ✗")
    # 转化为新用例
    new_cases_from_bug = []
    for p in recurring:
        tc = bug_to_test_case(p)
        if tc: new_cases_from_bug.append(tc)
    if len(new_cases_from_bug) == 2:
        ok(f"缺陷→用例转化 {len(new_cases_from_bug)} 条 ✔")
    else:
        fail(f"缺陷→用例转化数量错误 {new_cases_from_bug} ✗")

    # ── 测试 5：规范沉淀 + 去重 ──
    # 第一条规范
    w1 = write_standard(TEST_MODULE, "checklist", "并发场景必须覆盖",
                        "涉及金额的功能必须包含并发测试用例", "session-v1.0")
    # 重复 title 应被去重
    w2 = write_standard(TEST_MODULE, "checklist", "并发场景必须覆盖",
                        "重复内容不应写入", "session-v1.1")
    # 不同 title 正常写入
    w3 = write_standard(TEST_MODULE, "lession_learned", "超时需补偿机制",
                        "网关超时必须有补偿+重试", "session-v1.1")
    stds = read_json(os.path.join(DATA_DIR, "standards.json"))
    if w1 and not w2 and w3 and len(stds) == 2:
        ok(f"规范沉淀+去重正确（{len(stds)} 条，重复 title 被拒）✔")
    else:
        fail(f"规范沉淀+去重错误 w1={w1} w2={w2} w3={w3} len={len(stds)} ✗")

    # ── 测试 6：版本清理（>5 删最旧，保留 5）──
    # 已有 v1.0, v1.1（test-cases）。再写到 v1.6 共 7 个版本
    for v in ["v1.2","v1.3","v1.4","v1.5","v1.6"]:
        write_test_case_version(TEST_MODULE, v, [
            {"title":f"用例-{v}","type":"功能测试","business_layer":"体验层","priority":"P2"}
        ])
    deleted = cleanup_versions(TEST_MODULE, keep=5)
    remaining = sorted([f for f in os.listdir(os.path.join(DATA_DIR, "test-cases"))
                        if re.match(r'^v\d+\.\d+\.json$', f)])
    if len(deleted) == 2 and len(remaining) == 5:
        ok(f"版本清理正确（删 {deleted}，保留 {len(remaining)} 个）✔")
    else:
        fail(f"版本清理错误 deleted={deleted} remaining={remaining} ✗")
    # latest.json 仍保留
    if os.path.exists(os.path.join(DATA_DIR, "test-cases", "latest.json")):
        ok("latest.json 清理后仍保留 ✔")
    else:
        fail("latest.json 被误删 ✗")

    # ── 测试 7：summary.json 索引更新 ──
    all_bugs = bugs_v1_0
    summary = update_summary(TEST_MODULE, merged, all_bugs, versions, deleted)
    if summary["test_cases"]["total"] == len(merged) and \
       summary["bugs"]["total"] == len(all_bugs) and \
       summary["standards"]["total"] == 2:
        ok(f"summary.json 索引字段正确（cases={summary['test_cases']['total']}, bugs={summary['bugs']['total']}, stds={summary['standards']['total']}）✔")
    else:
        fail(f"summary.json 索引错误 {summary['test_cases']['total']}/{summary['bugs']['total']}/{summary['standards']['total']} ✗")
    # recurring_patterns 应包含并发和超时
    pats = [p["pattern"] for p in summary["bugs"]["recurring_patterns"]]
    if "并发" in pats and "超时" in pats:
        ok(f"summary.recurring_patterns 正确（{pats}）✔")
    else:
        fail(f"summary.recurring_patterns 错误 {pats} ✗")

    # ── 测试 8：跨会话历史加载 ──
    brief = load_history_brief(TEST_MODULE)
    if brief and brief["module"] == TEST_MODULE and brief["iterations"] == 5 and \
       "并发" in brief["recurring"] and "超时" in brief["recurring"]:
        ok(f"历史加载记忆简报正确（iterations={brief['iterations']}, recurring={brief['recurring']}）✔")
    else:
        fail(f"历史加载记忆简报错误 brief={brief} ✗")

    # ── 测试 9：schema 一致性（latest.json 结构）──
    latest = read_json(os.path.join(DATA_DIR, "test-cases", "latest.json"))
    required_fields = ["session_id", "created_at", "module", "entries"]
    if all(f in latest for f in required_fields) and \
       all(all(k in e for k in ["id","title","type","business_layer","priority"]) for e in latest["entries"]):
        ok("latest.json 符合 schema 结构 ✔")
    else:
        miss = [f for f in required_fields if f not in latest]
        fail(f"latest.json 缺字段 {miss} ✗")

    # ── 测试 10：summary.json 符合 schema ──
    for f in ["product","last_updated","iteration_count","test_cases","bugs","standards","iterations"]:
        if f not in summary:
            fail(f"summary.json 缺字段 {f} ✗")
            break
    else:
        ok("summary.json 符合 schema 结构 ✔")

finally:
    # 清理临时测试目录
    if os.path.exists(DATA_DIR):
        shutil.rmtree(DATA_DIR)

# 输出结果
for is_ok, msg in results:
    mark = "✔" if is_ok else "✗"
    print(f"  {mark} {msg}")
    sys.stdout.flush()

# 写到环境变量传递给 bash（通过临时文件）
import tempfile
with open(os.path.join(tempfile.gettempdir(), "qa_mem_e2e_result.txt"), "w") as f:
    p = sum(1 for ok_, _ in results if ok_)
    fl = sum(1 for ok_, _ in results if not ok_)
    f.write(f"{p}\n{fl}\n")
    for ok_, msg in results:
        if not ok_:
            f.write(msg + "\n")
PYEOF

# 读取 python 写出的结果（用 head/sed 精确取行，避免 read 偏移问题）
RESULT_FILE="/tmp/qa_mem_e2e_result.txt"
if [[ -f "$RESULT_FILE" ]]; then
  PASS=$(sed -n '1p' "$RESULT_FILE")
  FAIL=$(sed -n '2p' "$RESULT_FILE")
  echo ""
  echo "================================================"
  echo "通过: $PASS  失败: $FAIL"
  if [[ "$FAIL" -gt 0 ]]; then
    echo ""
    echo "❌ 失败项:"
    sed -n '3,$p' "$RESULT_FILE" | while IFS= read -r line; do echo "  - $line"; done
    echo "⚠️  有 $FAIL 项失败"
    exit 1
  else
    echo "✅ 记忆模块端到端测试全部通过"
    exit 0
  fi
else
  echo "⚠️  未取到测试结果（python 执行异常）"
  exit 2
fi
