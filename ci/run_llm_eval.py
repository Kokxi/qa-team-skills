#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
qa-team-skills 真·LLM 端到端评测器（P0）

把 functional-eval.json 的每条 eval 真调 LLM 跑一遍：
  1. 解析 prompt 开头的 /qa-xxx → 加载 prompts/xxx/prompt.md 作为 system prompt
  2. prompt 剩余部分作为 user message 发给 LLM
  3. 拿到输出后，用 LLM-as-judge 按每条 assertion 判定 pass/fail
  4. 归档报告到 evals/history/llm-report-<version>-<时间戳>.json

使用方式：
  export OR_KEY="sk-or-..."            # 必填，绝不写入文件（OpenRouter）
  python ci/run_llm_eval.py                    # 跑全量 functional-eval
  python ci/run_llm_eval.py --smoke            # 只跑第一条（冒烟）
  python ci/run_llm_eval.py --eval evals/_smoke.json --concurrency 1
  python ci/run_llm_eval.py --worker-model cohere/north-mini-code:free --judge-model cohere/north-mini-code:free

注意：本脚本不写入 API key 到任何文件，仅从环境变量读取。
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

# ── 配置 ─────────────────────────────────────────────
DEFAULT_BASE_URL = "https://openrouter.ai/api/v1"
DEFAULT_MODEL = "cohere/north-mini-code:free"
DEFAULT_TIMEOUT = 150
DEFAULT_CONCURRENCY = 2
# API key 环境变量名（OpenRouter 用 OR_KEY 或 OPENROUTER_API_KEY）
API_KEY_ENV = ["OR_KEY", "OPENROUTER_API_KEY"]

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SKILL_DIR = os.path.dirname(SCRIPT_DIR)
VERSION = open(os.path.join(SKILL_DIR, "VERSION"), encoding="utf-8").read().strip().lstrip("v")


def now_iso():
    return datetime.now(timezone.utc).isoformat()


# ── LLM 调用 ─────────────────────────────────────────
def llm_chat(base_url, api_key, model, messages, timeout, max_tokens=8192, temperature=0.3):
    """调用 chat completions，返回 (content, finish, usage, reasoning)。
    注：max_tokens 默认 8192（cohere/north-mini-code:free 实测可完整产出结构化报告）；
    若用 reasoning 模型（如 glm-5.2/kimi-for-coding）需调到 16384+ 并改 temperature=1。"""
    url = f"{base_url}/chat/completions"
    body = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,  # 0.3 评测稳定；reasoning 模型（kimi/glm）需改为 1
    }
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            d = json.load(resp)
        msg = d["choices"][0]["message"]
        content = msg.get("content", "") or ""
        reasoning = msg.get("reasoning_content", "") or ""
        finish = d["choices"][0].get("finish_reason", "")
        usage = d.get("usage", {})
        return content, finish, usage, reasoning
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code}: {body[:300]}")
    except Exception as e:
        raise RuntimeError(f"请求失败: {e}")


def llm_chat_retry(base_url, api_key, model, messages, timeout, retries=2, max_tokens=8192):
    """带重试的调用（应对限流/网络抖动）"""
    last_err = None
    for i in range(retries + 1):
        try:
            return llm_chat(base_url, api_key, model, messages, timeout, max_tokens=max_tokens)
        except Exception as e:
            last_err = e
            if i < retries:
                time.sleep(3 * (i + 1))  # 3s, 6s 退避
    raise last_err


# ── Prompt 装配 ──────────────────────────────────────
# /qa-xxx → prompts/xxx/prompt.md 映射
CMD_TO_PROMPT = {
    "/qa-prd": "prd",
    "/qa-case": "case",
    "/qa-bug": "bug",
    "/qa-report": "report",
    "/qa-team": "team",
    "/qa-agent": "agent",
    "/qa-explore": "explore",
    "/qa": "qa",
}


def load_system_prompt(cmd):
    """根据 /qa-xxx 指令加载对应 prompt.md 作为 system prompt"""
    sub = CMD_TO_PROMPT.get(cmd)
    if not sub:
        return None, f"未知指令: {cmd}"
    path = os.path.join(SKILL_DIR, "prompts", sub, "prompt.md")
    if not os.path.exists(path):
        return None, f"prompt 文件不存在: {path}"
    with open(path, encoding="utf-8") as f:
        return f.read(), None


def parse_eval_prompt(prompt_text):
    """解析 eval 的 prompt 字段：开头 /qa-xxx 是指令，剩余是用户输入"""
    # 匹配开头的 /qa-xxx（含 /qa）
    m = re.match(r"^(/qa[a-z\-]*)\s*\n?(.*)", prompt_text, re.DOTALL)
    if not m:
        return None, None, "prompt 不以 /qa-xxx 开头"
    cmd = m.group(1)
    user_input = m.group(2).strip()
    return cmd, user_input, None


# ── Judge 判定 ───────────────────────────────────────
JUDGE_SYSTEM = """你是一个严格的测试质量评审员。你会收到一份 AI 生成的测试产出和一条断言。
你的任务：判断该产出是否满足这条断言。

只输出一行 JSON，格式严格如下：
{"pass": true, "reason": "简要说明为什么通过"}
或
{"pass": false, "reason": "简要说明为什么不通过"}

不要输出任何其他内容。"""


def judge_assertion(base_url, api_key, judge_model, output, assertion, timeout):
    """用 LLM 判定单条 assertion 是否通过。返回 (pass: bool, reason: str)
    注：kimi-for-coding 是 reasoning 模型，reasoning_content 占大量 token，
    judge 的 max_tokens 需设到 800 才能保证 content 不被截断。"""
    user_msg = f"""## 待评定的 AI 产出
{output[:6000]}

## 断言
- 名称: {assertion['name']}
- 期望满足: {assertion['expected']}
- 说明: {assertion['description']}

请判断产出是否满足这条断言（expected=true 表示应满足，expected=false 表示不应出现）。
只输出一行 JSON。"""
    messages = [
        {"role": "system", "content": JUDGE_SYSTEM},
        {"role": "user", "content": user_msg},
    ]
    try:
        content, _, _, _ = llm_chat_retry(base_url, api_key, judge_model, messages, timeout, max_tokens=2048)
        content = (content or "").strip()
        if not content:
            return False, "judge content 为空（可能 max_tokens 被 reasoning 耗尽）"
        # 增强 JSON 解析：从 content 提取最外层 {...}（支持多行/带空白）
        # 先试单行紧凑格式
        m = re.search(r'\{[^{}]*"pass"[^{}]*\}', content, re.DOTALL)
        if not m:
            # 再试提取首个 { 到最后一个 }（多行 JSON）
            start = content.find("{")
            end = content.rfind("}")
            if start != -1 and end != -1 and end > start:
                candidate = content[start:end+1]
                try:
                    obj = json.loads(candidate)
                    is_pass = bool(obj.get("pass", False))
                    reason = str(obj.get("reason", ""))[:200]
                    return is_pass, reason
                except json.JSONDecodeError:
                    pass
            return False, f"judge 输出无法解析: {content[:120]}"
        obj = json.loads(m.group(0))
        is_pass = bool(obj.get("pass", False))
        reason = str(obj.get("reason", ""))[:200]
        return is_pass, reason
    except Exception as e:
        return False, f"judge 调用失败: {e}"


# ── 单条 eval 执行 ───────────────────────────────────
def run_one_eval(base_url, api_key, worker_model, judge_model, eval_item, timeout):
    """跑一条 eval：调 worker 生成产出 → judge 逐条判定 assertion。返回结果 dict。"""
    eid = eval_item.get("id", "?")
    name = eval_item.get("name", "")
    prompt_text = eval_item["prompt"]
    assertions = eval_item.get("assertions", [])

    result = {
        "id": eid,
        "name": name,
        "assertions": [],
        "pass_count": 0,
        "fail_count": 0,
        "error": None,
    }

    # 1. 解析指令 + 装配 system prompt
    cmd, user_input, err = parse_eval_prompt(prompt_text)
    if err:
        result["error"] = f"prompt 解析失败: {err}"
        result["fail_count"] = len(assertions)
        return result

    sys_prompt, err = load_system_prompt(cmd)
    if err:
        result["error"] = f"system prompt 加载失败: {err}"
        result["fail_count"] = len(assertions)
        return result

    # 2. 调 worker 生成产出
    messages = [
        {"role": "system", "content": sys_prompt},
        {"role": "user", "content": user_input},
    ]
    try:
        output, finish, usage, reasoning = llm_chat_retry(base_url, api_key, worker_model, messages, timeout)
        # 兜底：kimi-for-coding 是 reasoning 模型，若 content 为空但 reasoning 有内容，
        # 用 reasoning 尾部作为产出（避免 judge 全部判"产出为空"）
        if not output.strip() and reasoning.strip():
            output = "[注: content 为空，回退用 reasoning 尾部]\n" + reasoning[-4000:]
            result["warning"] = "worker content 为空，已回退用 reasoning 尾部"
        result["output_preview"] = output[:500]
        result["finish_reason"] = finish
        result["usage"] = usage
        if finish == "length":
            w = result.get("warning", "")
            result["warning"] = (w + "; " if w else "") + "输出被 max_tokens 截断，可能影响判定"
    except Exception as e:
        result["error"] = f"worker 调用失败: {e}"
        result["fail_count"] = len(assertions)
        return result

    # 3. judge 逐条判定
    for asser in assertions:
        is_pass, reason = judge_assertion(base_url, api_key, judge_model, output, asser, timeout)
        # 注意：assertion.expected=false 表示"不应出现"，judge 直接判 pass/fail 已考虑此语义
        result["assertions"].append({
            "name": asser["name"],
            "expected": asser["expected"],
            "pass": is_pass,
            "reason": reason,
        })
        if is_pass:
            result["pass_count"] += 1
        else:
            result["fail_count"] += 1

    return result


# ── 主流程 ───────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="qa-team-skills 真·LLM 端到端评测器")
    parser.add_argument("--eval", default="evals/functional-eval.json", help="评测集 JSON 文件")
    parser.add_argument("--smoke", action="store_true", help="只跑第一条（冒烟）")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--worker-model", default=DEFAULT_MODEL, help="生成产出的模型")
    parser.add_argument("--judge-model", default=DEFAULT_MODEL, help="判定的模型")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)
    parser.add_argument("--concurrency", type=int, default=DEFAULT_CONCURRENCY)
    parser.add_argument("--no-archive", action="store_true", help="不写归档报告")
    args = parser.parse_args()

    api_key = os.environ.get("OR_KEY") or os.environ.get("OPENROUTER_API_KEY")
    if not api_key:
        print("❌ 未设置 OR_KEY 或 OPENROUTER_API_KEY 环境变量", file=sys.stderr)
        print("   请先运行: export OR_KEY=\"sk-or-...\"", file=sys.stderr)
        sys.exit(2)

    # 读评测集
    eval_path = args.eval
    if not os.path.isabs(eval_path):
        eval_path = os.path.join(SKILL_DIR, eval_path)
    with open(eval_path, encoding="utf-8") as f:
        eval_data = json.load(f)

    # 兼容两种格式：functional-eval.json (对象含 evals 数组) / _smoke.json (数组)
    if isinstance(eval_data, dict):
        evals = eval_data.get("evals", [])
        eval_version = eval_data.get("version", VERSION)
    else:
        evals = eval_data
        eval_version = VERSION

    if args.smoke:
        evals = evals[:1]

    total = len(evals)
    print(f"🤖 qa-team-skills v{VERSION} 真·LLM 端到端评测")
    print(f"   评测集: {os.path.basename(eval_path)} ({eval_version}, {total} 条)")
    print(f"   worker: {args.worker_model} / judge: {args.judge_model}")
    print(f"   并发: {args.concurrency} / 超时: {args.timeout}s")
    print("=" * 50)
    sys.stdout.flush()

    start = time.time()
    results = []

    # 并发执行（每条 eval 独立，内部 judge 顺序）
    with ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        futures = {
            pool.submit(run_one_eval, args.base_url, api_key, args.worker_model,
                        args.judge_model, ev, args.timeout): ev for ev in evals
        }
        for i, fut in enumerate(as_completed(futures), 1):
            ev = futures[fut]
            try:
                r = fut.result()
            except Exception as e:
                r = {"id": ev.get("id", "?"), "name": ev.get("name", ""),
                     "error": str(e), "pass_count": 0, "fail_count": len(ev.get("assertions", [])),
                     "assertions": []}
            results.append(r)
            status = "✅" if r["fail_count"] == 0 and not r.get("error") else "❌"
            err = f" [ERROR: {r['error']}]" if r.get("error") else ""
            print(f"  [{i}/{total}] {status} {r['id']} {r['name']} — 通过 {r['pass_count']}/{r['pass_count']+r['fail_count']}{err}")
            sys.stdout.flush()

    elapsed = time.time() - start

    # 汇总
    total_pass = sum(r["pass_count"] for r in results)
    total_fail = sum(r["fail_count"] for r in results)
    total_assertions = total_pass + total_fail
    accuracy = (total_pass / total_assertions * 100) if total_assertions else 0
    error_count = sum(1 for r in results if r.get("error"))

    print()
    print("=" * 50)
    print(f"通过断言: {total_pass}/{total_assertions} = {accuracy:.1f}%")
    print(f"eval 失败(有 error): {error_count}/{total}")
    print(f"耗时: {elapsed:.1f}s")

    # 失败明细
    failed = [r for r in results if r["fail_count"] > 0 or r.get("error")]
    if failed:
        print()
        print("❌ 失败项明细:")
        for r in failed:
            if r.get("error"):
                print(f"  - {r['id']} {r['name']}: ERROR — {r['error']}")
            for a in r.get("assertions", []):
                if not a["pass"]:
                    print(f"  - {r['id']}/{a['name']}: {a['reason']}")

    # 归档报告
    if not args.no_archive:
        report = {
            "version": VERSION,
            "eval_set": os.path.basename(eval_path),
            "timestamp": now_iso(),
            "config": {
                "worker_model": args.worker_model,
                "judge_model": args.judge_model,
                "concurrency": args.concurrency,
                "smoke": args.smoke,
            },
            "summary": {
                "total_evals": total,
                "total_assertions": total_assertions,
                "pass": total_pass,
                "fail": total_fail,
                "accuracy": f"{accuracy:.1f}%",
                "errors": error_count,
                "elapsed_sec": round(elapsed, 1),
            },
            "results": results,
        }
        hist_dir = os.path.join(SKILL_DIR, "evals", "history")
        os.makedirs(hist_dir, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        tag = "-smoke" if args.smoke else ""
        report_file = os.path.join(hist_dir, f"llm-report-{VERSION}-{ts}{tag}.json")
        with open(report_file, "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
        print(f"\n📋 报告已归档: {report_file}")

    # 退出码：有 error 或准确率 < 70% 视为失败
    if error_count > 0 or accuracy < 70:
        sys.exit(1)
    print("✅ 评测通过（准确率 ≥ 70% 且无 error）")


if __name__ == "__main__":
    main()
