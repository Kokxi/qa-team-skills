#!/usr/bin/env bash
# qa-team-skills 记忆模块长期积累压测（P1）
# 用途：模拟 10 轮迭代持续写入，验证 summary.json 无性能退化、无重复堆积
# 使用方式：在 qa-team-skills 目录下运行 bash ci/test-memory-stress.sh
# 验证项：
#   1. summary.json 体积线性增长（非爆炸）
#   2. 读取延迟不退化（第 1 轮 vs 第 10 轮 ≤ 3x）
#   3. 无重复条目堆积（latest.json 去重生效）
#   4. 版本清理生效（保留最近 5 个版本）
#   5. standards.json 标题去重（P1 去重硬保护）
set -uo pipefail

# Windows + Git Bash：强制 Python 以 UTF-8 输出，否则默认 GBK 编码会导致
# ✔ 等符号打印抛 UnicodeEncodeError，污染退出码（预存 bug，与 run-evals.sh 同源）
export PYTHONIOENCODING=utf-8
export LC_ALL=C.UTF-8

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

PY=python
if ! command -v $PY >/dev/null 2>&1; then PY=python3; fi

echo "⚡ qa-team-skills 记忆模块长期积累压测（10 轮迭代）"
echo "================================================"

$PY - "$SKILL_DIR" <<'PYEOF'
import json, os, sys, shutil, time, re, hashlib
from datetime import datetime, timezone

SKILL_DIR = sys.argv[1]
TEST_MODULE = "stress-test-module"
DATA_DIR = os.path.join(SKILL_DIR, "memory", "data", "products", TEST_MODULE)
if os.path.exists(DATA_DIR):
    shutil.rmtree(DATA_DIR)

results = []
def ok(msg):  results.append((True, msg))
def fail(msg): results.append((False, msg))

def now_iso(): return datetime.now(timezone.utc).isoformat()

def write_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)

def read_json(path):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

# ── 复刻记忆模块规则（与 test-memory-e2e.sh 一致）────────────
def write_tc_version(module, version, entries):
    write_json(os.path.join(DATA_DIR, "test-cases", f"{version}.json"), {
        "session_id": f"session-{version}", "created_at": now_iso(),
        "module": module, "entries": entries
    })

def merge_latest(module):
    """合并：优先读现有 latest.json 作为基线（避免版本清理后丢早期唯一用例），
    再并入磁盘上各版本文件的新增用例，按标题 hash 去重。"""
    tc_dir = os.path.join(DATA_DIR, "test-cases")
    latest_path = os.path.join(tc_dir, "latest.json")
    seen = {}
    merged = []
    # 1. 先读现有 latest.json 作为基线（保留被清理版本的唯一用例）
    if os.path.exists(latest_path):
        old = read_json(latest_path)
        for e in old.get("entries", []):
            key = hashlib.md5(e["title"].encode('utf-8')).hexdigest()
            if key not in seen:
                seen[key] = True
                merged.append(dict(e))
    # 2. 再并入磁盘上各版本文件
    versions = sorted([f for f in os.listdir(tc_dir) if re.match(r'^v\d+\.\d+\.json$', f)])
    for v in versions:
        data = read_json(os.path.join(tc_dir, v))
        for e in data.get("entries", []):
            key = hashlib.md5(e["title"].encode('utf-8')).hexdigest()
            if key not in seen:
                seen[key] = True
                e_copy = dict(e)
                e_copy["source_version"] = v.replace(".json", "")
                merged.append(e_copy)
    for i, e in enumerate(merged, 1):
        e["id"] = f"TC{i:03d}"
    write_json(latest_path, {
        "session_id": f"merge-{datetime.now(timezone.utc).strftime('%Y%m%d')}",
        "created_at": now_iso(), "module": module, "entries": merged
    })
    return merged

def cleanup_versions(module, keep=5):
    tc_dir = os.path.join(DATA_DIR, "test-cases")
    versions = sorted([f for f in os.listdir(tc_dir) if re.match(r'^v\d+\.\d+\.json$', f)])
    if len(versions) <= keep:
        return []
    to_delete = versions[:-keep]
    for f in to_delete:
        os.remove(os.path.join(tc_dir, f))
    return to_delete

def write_standard_hash_dedup(module, category, title, content, source):
    """规范沉淀 + 标题 hash 去重（P1 去重硬保护）"""
    path = os.path.join(DATA_DIR, "standards.json")
    stds = read_json(path) if os.path.exists(path) else []
    title_hash = hashlib.md5(title.encode('utf-8')).hexdigest()
    if any(s.get("title_hash") == title_hash for s in stds):
        return False
    stds.append({
        "category": category, "title": title, "title_hash": title_hash,
        "content": content, "source": source
    })
    write_json(path, stds)
    return True

def update_summary(module, merged_cases):
    by_type = {"功能测试":0,"边界测试":0,"异常测试":0,"安全测试":0,"性能测试":0,"兼容性测试":0}
    by_layer = {"核心层":0,"体验层":0,"增值层":0}
    for e in merged_cases:
        if e.get("type") in by_type: by_type[e["type"]] += 1
        if e.get("business_layer") in by_layer: by_layer[e["business_layer"]] += 1
    tc_dir = os.path.join(DATA_DIR, "test-cases")
    remaining = sorted([f.replace(".json","") for f in os.listdir(tc_dir) if re.match(r'^v\d+\.\d+\.json$', f)])
    stds = read_json(os.path.join(DATA_DIR, "standards.json")) if os.path.exists(os.path.join(DATA_DIR, "standards.json")) else []
    summary = {
        "product": module, "last_updated": now_iso(),
        "iteration_count": len(remaining),
        "test_cases": {"total": len(merged_cases), "versions": remaining,
                       "by_type": by_type, "by_layer": by_layer},
        "standards": {"total": len(stds)},
    }
    write_json(os.path.join(DATA_DIR, "summary.json"), summary)
    return summary

# ══════════════════════════════════════════════════════
# 压测：10 轮迭代，每轮写入 5 条用例（含重复）+ 1 条规范（含重复）
# ══════════════════════════════════════════════════════
try:
    ROUNDS = 10
    summary_sizes = []      # 每轮 summary.json 字节数
    read_latencies = []     # 每轮读取 summary.json 耗时（ms）
    latest_counts = []      # 每轮 latest.json 用例数
    std_counts = []         # 每轮 standards.json 条数

    for i in range(1, ROUNDS + 1):
        version = f"v1.{i-1}"
        # 每轮 5 条用例：3 条新 + 2 条重复（验证去重）
        entries = [
            {"title": f"用例-{i}-A", "type": "功能测试", "business_layer": "核心层", "priority": "P0"},
            {"title": f"用例-{i}-B", "type": "边界测试", "business_layer": "体验层", "priority": "P1"},
            {"title": f"用例-{i}-C", "type": "安全测试", "business_layer": "核心层", "priority": "P0"},
            # 重复标题（应被去重）
            {"title": "用例-1-A", "type": "功能测试", "business_layer": "核心层", "priority": "P0"},
            {"title": "用例-1-B", "type": "边界测试", "business_layer": "体验层", "priority": "P1"},
        ]
        write_tc_version(TEST_MODULE, version, entries)
        merged = merge_latest(TEST_MODULE)
        cleanup_versions(TEST_MODULE, keep=5)
        summary = update_summary(TEST_MODULE, merged)

        # 每轮写 1 条规范（第 3、6、9 轮写重复标题，验证 hash 去重）
        if i in (3, 6, 9):
            write_standard_hash_dedup(TEST_MODULE, "checklist", "并发场景必须覆盖",
                                      "重复内容", f"session-{version}")
        else:
            write_standard_hash_dedup(TEST_MODULE, "checklist", f"规范-{i}",
                                      f"内容-{i}", f"session-{version}")

        # 测量：summary.json 体积 + 读取延迟
        summary_path = os.path.join(DATA_DIR, "summary.json")
        summary_sizes.append(os.path.getsize(summary_path))
        t0 = time.perf_counter()
        read_json(summary_path)
        read_latencies.append((time.perf_counter() - t0) * 1000)  # ms
        latest_counts.append(len(merged))
        stds = read_json(os.path.join(DATA_DIR, "standards.json"))
        std_counts.append(len(stds))

    # ── 断言 1：summary.json 体积线性增长（非爆炸）──
    # 10 轮后体积应 ≤ 第 1 轮的 5 倍（线性而非指数）
    ratio_size = summary_sizes[-1] / summary_sizes[0] if summary_sizes[0] else 0
    if ratio_size <= 5:
        ok(f"summary.json 体积线性增长（第 1 轮 {summary_sizes[0]}B → 第 10 轮 {summary_sizes[-1]}B，比值 {ratio_size:.1f}x ≤ 5x）✔")
    else:
        fail(f"summary.json 体积爆炸（{summary_sizes[0]}B → {summary_sizes[-1]}B，比值 {ratio_size:.1f}x > 5x）✗")

    # ── 断言 2：读取延迟不退化 ──
    # 第 10 轮延迟应 ≤ 第 1 轮的 3 倍
    ratio_lat = read_latencies[-1] / read_latencies[0] if read_latencies[0] else 0
    if ratio_lat <= 3:
        ok(f"读取延迟无退化（第 1 轮 {read_latencies[0]:.2f}ms → 第 10 轮 {read_latencies[-1]:.2f}ms，比值 {ratio_lat:.1f}x ≤ 3x）✔")
    else:
        fail(f"读取延迟退化（{read_latencies[0]:.2f}ms → {read_latencies[-1]:.2f}ms，比值 {ratio_lat:.1f}x > 3x）✗")

    # ── 断言 3：无重复条目堆积 ──
    # 10 轮共写 50 条用例（含 20 条重复标题），去重后唯一标题数 = 30（每轮 3 个新标题 × 10 轮）
    # 注：版本清理删除旧版本文件，但 merge_latest 以旧 latest.json 为基线，唯一用例不丢
    expected_unique = 30  # 3 新标题/轮 × 10 轮
    if latest_counts[-1] == expected_unique:
        ok(f"latest.json 去重生效（写入 50 条含 20 重复 → 合并 {latest_counts[-1]} 条唯一）✔")
    else:
        fail(f"latest.json 去重异常（期望 {expected_unique} 条，实际 {latest_counts[-1]} 条）✗")

    # ── 断言 4：版本清理生效（保留最近 5 个）──
    tc_dir = os.path.join(DATA_DIR, "test-cases")
    versions = sorted([f for f in os.listdir(tc_dir) if re.match(r'^v\d+\.\d+\.json$', f)])
    if len(versions) == 5:
        ok(f"版本清理生效（10 轮写入后保留最近 5 个版本：{versions}）✔")
    else:
        fail(f"版本清理异常（期望保留 5 个，实际 {len(versions)} 个：{versions}）✗")

    # ── 断言 5：standards.json 标题 hash 去重（P1 去重硬保护）──
    # 10 轮写入：8 条新标题（轮 1,2,3,4,5,7,8,10 — 轮 3 首次写"并发场景必须覆盖"算新）
    # + 3 条重复（轮 6,9 重复"并发场景必须覆盖"，应被 hash 拦截）→ 应剩 8 条
    if std_counts[-1] == 8:
        ok(f"standards.json 标题 hash 去重生效（10 轮写入含 2 重复 → {std_counts[-1]} 条）✔")
    else:
        fail(f"standards.json 去重异常（期望 8 条，实际 {std_counts[-1]} 条）✗")

    # ── 断言 6：latest.json 在版本清理后仍含全部去重用例 ──
    latest = read_json(os.path.join(tc_dir, "latest.json"))
    if len(latest["entries"]) == 30:
        ok(f"latest.json 清理后保留全部合并数据（30 条，未因版本删除丢失）✔")
    else:
        fail(f"latest.json 在版本清理后丢数据（期望 30 条，实际 {len(latest['entries'])} 条）✗")

finally:
    if os.path.exists(DATA_DIR):
        shutil.rmtree(DATA_DIR)

# 输出
for is_ok, msg in results:
    mark = "✔" if is_ok else "✗"
    print(f"  {mark} {msg}")
import tempfile
with open(os.path.join(tempfile.gettempdir(), "qa_mem_stress_result.txt"), "w") as f:
    p = sum(1 for ok_, _ in results if ok_)
    fl = sum(1 for ok_, _ in results if not ok_)
    f.write(f"{p}\n{fl}\n")
    for ok_, msg in results:
        if not ok_: f.write(msg + "\n")
PYEOF

RESULT_FILE="/tmp/qa_mem_stress_result.txt"
PASS=$(sed -n '1p' "$RESULT_FILE")
FAIL=$(sed -n '2p' "$RESULT_FILE")
echo ""
echo "================================================"
echo "通过: $PASS  失败: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  echo ""
  echo "❌ 失败项:"
  sed -n '3,$p' "$RESULT_FILE" | while IFS= read -r line; do echo "  - $line"; done
  exit 1
else
  echo "✅ 长期积累压测全部通过（10 轮迭代无性能退化/无重复堆积）"
  exit 0
fi
