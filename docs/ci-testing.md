# CI 与质量验证

qa-team-skills 是纯 Prompt 形态的 AI 技能，无 HTTP API 可调。质量验证由三套互补的脚本构成，覆盖从静态结构到动态行为的不同层面。

## 验证脚本总览

| 脚本 | 验证层面 | 验证什么 | 耗时 |
|------|---------|---------|------|
| `ci/validate.sh` | 静态结构 | 文件齐全、SKILL.md 字段、prompt 必含章节、无硬编码行业词、版本一致 | < 1s |
| `ci/run-evals.sh` | 动态契约 | 触发评测（规则路由基线）+ prompt↔eval 契约断言 + 归档报告 | ~ 2s |
| `ci/test-memory-e2e.sh` | 行为模拟 | 记忆模块全生命周期：写入/合并/清理/转化/规范沉淀/历史加载 | ~ 1s |
| `ci/run_llm_eval.py` | **真·LLM 端到端** | 接 LLM API 真调 skill，LLM-as-judge 按 assertion 判定产出内容质量 | ~ 4-6 分钟（8 条 eval） |

## 使用方式

任何 prompt 或结构改动后，依次跑三套脚本：

```bash
bash ci/validate.sh          # 静态结构校验
bash ci/run-evals.sh         # 触发评测 + 契约断言
bash ci/test-memory-e2e.sh   # 记忆模块端到端
```

三套全过 = 当前版本质量基线达标。

## 各脚本说明

### ci/validate.sh

检查项目结构完整性，由 `ci/forbidden.txt` 定义禁止硬编码的行业词清单。

**检查项**：
- 必需文件齐全（SKILL.md、7 个 prompt、模板、docs、examples）
- 每个 prompt 含「防注入声明」「输出前自检」章节
- case/agent prompt 含「设计方法」字段
- prompts/SKILL.md 中无硬编码行业词（等保/三权分立/堡垒机等）
- VERSION 文件与 SKILL.md frontmatter 版本一致
- 无旧 prompt 目录残留（prompts/req-analyze、prompts/case-gen）

### ci/run-evals.sh

把 `evals/` 下的评测数据集变成可执行的评测。

**两类检查**：

1. **触发评测（规则路由基线）** — 读 `evals/trigger-eval.json`，用 `prompts/qa/intent-rules.md` 的关键词规则跑路由，对照期望算准确率。这是 LLM 路由的对照下限——**LLM 路由准确率应 ≥ 此规则基线才算合格**。当前基线 38/38 = 100%。

2. **契约断言（prompt↔eval）** — 把 `evals/functional-eval.json` 的 assertion 翻译成对 prompt 文件的 37 条静态检查，捕获"prompt 定义与 eval 期望"不一致（如标题写 10 个维度但 eval 要求 11 个）。当前 37/37 全过。

**归档报告**：每次运行输出 `evals/history/report-<version>-<时间戳>.json`，供跨版本对比，发现退化。

**Windows 注意**：脚本自动回退 `python`（`python3` 在 Windows 常是 Store 占位符），并清除 CRLF 换行避免字符串比较失败。

### ci/test-memory-e2e.sh

验证 `memory/README.md` 定义的记忆生命周期规则。用一个 python 模拟器复刻规则，在临时产品目录 `memory/data/products/e2e-test-module/` 上跑完整生命周期（测试完自动清理）。

**14 项断言覆盖**：

| # | 验证的行为 | 对应 README 章节 |
|---|----------|----------------|
| 1 | 首次写入创建目录结构 | 架构 |
| 2 | 增量写入多版本文件 | 增量写入 |
| 3 | 合并去重（同标题保留最早） | 汇总快照 |
| 4 | 重新编号 TC001..TCNNN | 汇总快照 |
| 5 | 复发检测（同类缺陷 ≥2 次） | 历史缺陷→用例转化 |
| 6 | 缺陷→用例转化 | 历史缺陷→用例转化 |
| 7 | 规范沉淀 + title 去重 | 规范库闭环 |
| 8 | 版本清理（>5 删最旧） | 版本清理规则 |
| 9 | latest.json 清理后仍保留 | 版本清理规则 |
| 10 | summary.json 索引字段正确 | 索引文件管理 |
| 11 | summary.recurring_patterns 正确 | 索引文件管理 |
| 12 | 跨会话历史加载记忆简报 | 跨会话历史加载 |
| 13 | latest.json 符合 schema | 数据模型 |
| 14 | summary.json 符合 schema | 数据模型 |

这是"规则契约测试"——确保 prompt 指令描述的记忆行为与 README 规范一致。真·AI 执行时的端到端验证（让真模型调 `/qa` 触发文件 I/O）需接模型 API，是后续工作。

### ci/run_llm_eval.py

**真·LLM 端到端评测**——前三套脚本的最高层补充。结构校验查"文件齐不齐"，契约断言查"prompt 定义对不对"，记忆测试查"规则实现对不对"，但都查不出"AI 真跑一遍产出质量好不好"。本脚本接 LLM API 真调 skill，用 LLM-as-judge 判定产出内容质量。

**工作流程**：
1. 解析 `functional-eval.json` 每条 eval 的 prompt 开头 `/qa-xxx` → 加载 `prompts/xxx/prompt.md` 作为 system prompt
2. prompt 剩余部分作为 user message 发给 worker 模型生成产出
3. 用 judge 模型按每条 assertion 判定 pass/fail（输出结构化 JSON）
4. 归档报告到 `evals/history/llm-report-<version>-<时间戳>.json`

**使用方式**：
```bash
export KIMI_API_KEY="sk-..."           # 必填，从环境变量读，绝不写入文件
python ci/run_llm_eval.py                    # 跑全量 functional-eval（8 条）
python ci/run_llm_eval.py --smoke            # 只跑第一条（冒烟，~50s）
python ci/run_llm_eval.py --concurrency 2    # 并发数（默认 2）
python ci/run_llm_eval.py --timeout 150      # 单次 LLM 调用超时（默认 120s）
```

**已验证发现的真实问题**（冒烟测试 prd-001）：
- `kimi-for-coding` 生成 prd 评审报告时**只列了 10 个维度，漏了第 11 个（业务分层）**——这是结构断言查不出、只有真调 LLM 才能发现的内容质量问题，说明 prompt 对"业务分层维度必输出"的约束需加强

**注意事项**：
- `kimi-for-coding` 是 reasoning 模型，`reasoning_content` 占大量 token，worker 的 `max_tokens` 需 ≥ 16k 才能保证 content 不被截断
- 模型仅允许 `temperature=1`
- 单条 eval 约 50s（1 次 worker + N 次 judge），全量 8 条并发 2 约 4-6 分钟
- API key 仅从 `$KIMI_API_KEY` 环境变量读，**脚本和归档报告均不写入 key**
- 退出码：准确率 < 70% 或有 error 视为失败

## 仍未覆盖的验证方法

| 方法 | 说明 | 优先级 |
|------|------|--------|
| 人工双盲评测 | 拉测试工程师对 AI 产出打分，验证"维度分析得对不对"（结构断言查不出） | P1（每版本一次） |
| 长期积累压测 | 模拟 5-10 轮迭代持续写入，断言 summary.json 无性能退化、无重复堆积 | P1 |
| 安全对抗评测集 | 针提示词注入、越权、数据外泄的对抗用例 | P2 |

## 集成到 CI 流水线

在 PR 合并前自动跑三套脚本，任一失败阻断合并：

```yaml
# .github/workflows/qa-skill-check.yml 示例
- name: 静态结构校验
  run: bash ci/validate.sh
- name: 评测 runner
  run: bash ci/run-evals.sh
- name: 记忆模块端到端
  run: bash ci/test-memory-e2e.sh
```

`run-evals.sh` 产生的 `evals/history/report-*.json` 可作为 artifact 归档，用于版本间准确率对比。
