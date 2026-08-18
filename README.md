# qa-team-skills

> 为测试团队设计的统一 AI 辅助能力——统一入口 /qa + 8 个标准化指令 + 记忆模块 + 完整验证体系，覆盖需求评审到团队管理。

[![Version](https://img.shields.io/badge/version-v1.6.1-blue)](./VERSION)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![skills.sh](https://skills.sh/b/Kokxi/qa-team-skills)](https://skills.sh/Kokxi/qa-team-skills)

***

## 为什么有这个项目？

测试团队普遍面临一个困境：**每个人用 AI 的方式不一样，输出的质量不一样**。

同样是需求评审，张三把 PRD 粘贴给 AI 得到 3 个问题，李四用另一种问法得到 15 个——不是需求本身差异大，是每个人的 Prompt 水平差异大。用例设计更是重灾区：有人只写 Happy Path，有人忘了边界值，新人完全不知道该问 AI 什么。团队越大，这个问题越严重。评审会上的精力不是花在"讨论问题"上，而是花在"对齐标准"上。

**qa-team-skills 解决的就是这个问题**：把测试团队最核心的 8 个工作环节——需求评审、用例设计、Agent 专项测试、缺陷分析、报告生成、团队管理、探索性测试——封装成 8 个标准化的 AI 指令。团队成员输入一样的东西，得到一样结构的输出。评审时的讨论对象从"格式对不对"变成了"问题有没有道理"。

***

## 设计思想

### 1. 嵌入流程，而非替代流程

qa-team-skills 不是一个"全自动测试平台"。它是一套嵌入现有研发流程的 AI 辅助工具。你仍然用 Jira 管理需求、用禅道跟踪缺陷、开评审会、写周报——这些不变。变的是**每个环节的 AI 辅助有了一致的标准**。

```
需求评审(/qa-prd) → 用例设计(/qa-case) → 缺陷分析(/qa-bug) → 报告生成(/qa-report) → 团队管理(/qa-team)
                    ↓
              Agent专项(/qa-agent)
```

对应的流程嵌入指南见 [`docs/process-integration.md`](./docs/process-integration.md)。

### 2. 防幻觉，不防思考

每个指令都内置了三层防御：

- **注入防护声明**：防止用户输入中的对抗性指令修改 AI 行为
- **约束规则**：必填字段缺失时拒绝输出，禁止 AI 自行编造
- **输出前自检清单**：AI 必须在输出前逐条核对，不通过不输出

但防御不等于限制——每条用例的设计方法仍是 AI 根据黑盒测试方法论自动选配的，评审维度仍是 AI 逐条扫描的。防的是幻觉，不是思考。

### 3. 业务分层：让测试优先级回归用户价值

传统的 P0-P3 优先级解决的是"这个用例不执行风险多大"。但我们团队引入了一个商业视角的维度——**业务分层**：

| 层级      | 定义              | 示例                |
| ------- | --------------- | ----------------- |
| **核心层** | 做不到这个，产品就没有存在价值 | 订单能否提交、支付能否成功     |
| **体验层** | 能用，但好不好用        | 错误提示是否清晰、操作步骤是否合理 |
| **增值层** | 锦上添花            | 动画效果、深色模式、社交分享    |

铅笔能不能写字是核心层，握笔舒不舒服是体验层，好不好看是增值层。在 `/qa-case` 中，每条用例同时标注业务分层和优先级——两个维度独立但互补，让测试资源分配不再拍脑袋。

### 4. 通用于任何行业

本技能不绑定安全、金融、ERP 等任何特定行业。核心流程 100% 通用。合规要求是可选输入——只有当你明确提供了行业标准（如 ISO 27001、GDPR、SOX），AI 才会在用例中追加密合检查点。行业配置参考文件（`team/roles.json`、`team/standards.json`）可自由定制。

### 5. 管理者视角：AI 用错了比不用更危险

SKILL.md 中专门有一章「人工校验规则」，不是给 AI 看的——是给人看的。P0 用例必须人工审阅、置信度"中/低"的根因分析必须有第二人复核、自动生成的报告数据必须与原始系统抽样核对。AI 的输出是辅助，最终的测试决策由人做出。

***

## 8 大指令

| 指令           | 做什么        | 适合谁        | 核心亮点                             |
| ------------ | ---------- | ---------- | -------------------------------- |
| `/qa`        | **统一入口** | 所有角色      | 自然语言→意图解析→任务编排→记忆管理→自动规划（v1.5）          |
| `/qa-prd`    | 需求评审       | 测试工程师、测试经理 | 11 维度系统扫描 + 业务分层建议 + 澄清问题清单      |
| `/qa-case`   | 测试用例设计     | 测试工程师      | 6 测试类型 × 9 黑盒方法 + 业务分层，自动交叉匹配    |
| `/qa-agent`  | AI 智能体专项测试 | 测试工程师      | 16 维度（含 RAG），覆盖幻觉/偷懒/稳定性/可控性     |
| `/qa-bug`    | 缺陷分析       | 测试工程师、开发   | 先评估描述质量 → 再分析根因，标注置信度，支持批量       |
| `/qa-report` | 报告生成       | 测试工程师      | 日报/周报/阶段/季度/专项，支持 Jira/禅道等系统数据 |
| `/qa-team`   | 团队管理       | 测试经理       | 11 项子能力，含进度看板/产出统计/准入准出/质量评估     |
| `/qa-explore` | 探索性测试     | 测试工程师      | 三阶段设计（Session 笔记→疑似 Bug/学习经验分流→Debrief 沉淀） |

***

## 适用人群

**测试团队（3 人以上）** — 统一 AI 辅助标准，评审效率更高，新人上手更快。
**已经有一套流程的团队** — 不改造你的流程，给每个环节配上标准化 AI 指令。
**内网/离线环境用户** — 核心 Prompt 无外部依赖（CI 评测脚本需外部 LLM API，可选不运行）

以下情况这个项目帮不了你：想全流程自动化的团队、不需要人工判断的环节、单打独斗的个人。

***

## 快速开始

### 安装

qa-team-skills 核心为纯 Prompt 工程，无外部依赖。提供三种安装方式：

#### 方式一：手动复制（通用）

将项目目录复制到对应 AI Agent 的 skills 路径：

| AI Agent             | 全局安装路径                       | 项目内路径                      | 兼容性              |
| -------------------- | ---------------------------- | -------------------------- | ---------------- |
| **Claude Code**      | `~/.claude/skills/`          | `.claude/skills/`          | ✅ 原生             |
| **OpenCode**         | `~/.config/opencode/skills/` | `.config/opencode/skills/` | ✅ 原生             |
| **GitHub Copilot**   | —                            | `.github/skills/`          | ✅ SKILL.md 标准    |
| **OpenAI Codex CLI** | `~/.agents/skills/`          | —                          | ✅ agentskills.io |
| **Cursor**           | —                            | `.cursor/skills/`          | ✅ 互通             |
| **Windsurf**         | —                            | —                          | ❌ 需转换格式          |

```bash
# 全局安装到 Claude Code（推荐）
cp -r qa-team-skills ~/.claude/skills/

# 项目内安装到 GitHub Copilot
cp -r qa-team-skills ./.github/skills/
```

> ⚠️ **关于 `/qa` 指令的说明**：本技能的 `/qa`、`/qa-prd` 等 8 个指令是**逻辑指令**（由 AI 根据 `prompts/qa/intent-rules.md` 的意图路由规则自动解析执行），**不是各 Agent 注册的斜杠命令**——命令面板的自动补全里看不到它们，安装后也不需要注册。日常使用直接用自然语言下达任务（如"帮我设计登录功能的测试用例"）即可触发，或显式输入 `/qa-case` 让 AI 按对应指令执行。如需在 Claude Code / OpenCode 中拥有真正的斜杠命令补全，可自行在 `.claude/commands/`（或对应 Agent 的 commands 目录）为 8 个指令各建一个命令文件。

#### 方式二：一键安装（npx skills）

```bash
npx skills add Kokxi/qa-team-skills
```

自动检测当前 Agent（Claude Code / OpenCode / Codex / Cursor 等 68+ 种），安装到正确位置。

#### 方式三：在 Agent 内搜索安装

在 OpenClaw 或支持 ClawHub 的 Agent 中：

```bash
/findskill qa-team-skills       # 发现技能
clawhub install qa-team-skills  # 安装技能
```

### 使用

```bash
/qa          # 自然语言下达测试任务 → 自动解析 → 路由 → 记忆管理 → 自动规划
/qa-prd      # 粘贴 PRD → 11 维度评审报告 + 业务分层建议
/qa-case     # 输入需求 → 6 类型 × 9 方法结构化用例
/qa-agent    # 描述 Agent → 16 维度专项测试用例（含 RAG）
/qa-bug      # 粘贴缺陷 → 质量评估 → 根因分析（支持批量）
/qa-report   # 填入数据 → 日报/周报/阶段报告
/qa-team     # 汇总团队数据 → 管理看板/趋势/产出
/qa-explore  # 探索性测试 → Session 笔记 → 疑似 Bug/学习经验分流 → Debrief 沉淀
```

### 示例

**[examples/](./examples/)** 目录包含全部 6 个指令的完整输入输出示例（均来自真实测试场景）：

| 示例                                          | 指令           | 场景                  |
| ------------------------------------------- | ------------ | ------------------- |
| [prd-demo.md](./examples/prd-demo.md)       | `/qa-prd`    | 订单改价需求评审，11 维度扫描    |
| [login-demo.md](./examples/login-demo.md)   | `/qa-case`   | 登录功能 35 条用例 × 3 业务层 |
| [case-demo.md](./examples/case-demo.md)     | `/qa-case`   | 订单改价，评审问题→用例转化      |
| [agent-demo.md](./examples/agent-demo.md)   | `/qa-agent`  | 智能客服 16 维度，含 RAG    |
| [bug-demo.md](./examples/bug-demo.md)       | `/qa-bug`    | 从被驳回 → 根因定位 + 批量    |
| [report-demo.md](./examples/report-demo.md) | `/qa-report` | 三段话 → 日报/周报/阶段报告    |
| [team-demo.md](./examples/team-demo.md)     | `/qa-team`   | 迭代末看板/产出/准出         |

***

## 项目结构

```
qa-team-skills/
├── SKILL.md                      # 技能入口：8 指令总览 + 架构概览 + 人工校验规则
├── VERSION                       # 当前版本
├── README.md                     # 本文件
├── LICENSE                       # MIT
├── prompts/                      # 8 个指令的 Prompt 定义
│   ├── qa/prompt.md             #   统一入口：意图解析 → 任务编排 → 记忆管理 → 自动规划
│   ├── qa/intent-rules.md       #   意图匹配规则（关键词→指令路由）
│   ├── qa/validation-rules.md   #   推理校验规则（各指令输出前自检清单）
│   ├── prd/prompt.md            #   需求评审（11 维度 + 业务分层）
│   ├── case/prompt.md           #   用例设计（9 方法 × 6 类型 + 业务分层 + 规范库联动）
│   ├── agent/prompt.md          #   Agent 专项（16 维度含 RAG）
│   ├── bug/prompt.md            #   缺陷分析（质量评估 + 根因 + 批量）
│   ├── report/prompt.md         #   报告生成（5 种）
│   ├── team/prompt.md           #   团队管理（11 子能力 + 路由）
│   └── explore/prompt.md        #   探索性测试（三阶段 + Session 笔记 + Debrief）★ v1.5 新增
├── memory/                       # 记忆模块（v1.4.0 新增）
│   ├── README.md                 #   模块说明（含合并/清理/去重规则）
│   ├── schema/                   #   6 个 JSON Schema 数据模型
│   └── data/products/            #   按产品模块沉淀的用例/缺陷/规范/报告库
├── templates/                    # 输出模板
│   ├── requirement.md            #   通用测试用例模板
│   ├── agent-test.md             #   Agent 专项模板（含中文 Payload）
│   └── error-output.md           #   统一错误格式
├── examples/
│   ├── README.md
│   └── *-demo.md                 # 7 个示例（覆盖全部 8 指令 + /qa 场景）
├── team/                         # 行业配置（可选引用）
│   ├── roles.json                #   角色映射
│   └── standards.json            #   合规标准参考
├── ci/                           # ★ 验证脚本金字塔（v1.5 完备）
│   ├── validate.sh               #   静态结构校验
│   ├── run-evals.sh              #   触发评测 + 契约断言
│   ├── test-memory-e2e.sh        #   记忆模块端到端（14 项断言）
│   ├── test-memory-stress.sh     #   长期积累压测（10 轮迭代 6 项断言）
│   ├── run_llm_eval.py           #   真·LLM 端到端评测（接 DeepSeek/OpenRouter/Kimi）
│   ├── forbidden.txt             #   禁止词列表
│   └── commit-msg.txt            #   提交规范
├── evals/                        # 评测数据集 + 历史归档
│   ├── functional-eval.json      #   功能评测集（8 条 eval + 契约断言）
│   ├── trigger-eval.json         #   触发评测集（38 条）
│   ├── security-eval.json        #   安全对抗评测集（8 条 7 种攻击）★ v1.5 新增
│   ├── _smoke.json               #   冒烟评测集
│   ├── human-review/             #   人工双盲评测方案（5 维度评分+双盲流程）
│   └── history/                  #   每轮评测归档报告（基线对比）
└── docs/
    ├── user-manual.md            # 完整使用手册
    ├── CHANGELOG.md              # 变更日志
    ├── process-integration.md    # 流程嵌入指南
    ├── version-policy.md         # 版本治理策略
    ├── ci-testing.md             # CI 与质量验证（6 套脚本金字塔）★ v1.5 新增
    └── agent-notes-skill-validation.md  # AI Agent 复用版经验文档 ★ v1.5 新增
```

***

## 适用场景

| 场景                | 推荐指令组合                                     |
| ----------------- | ------------------------------------------ |
| **新需求从零开始**       | `/qa-prd` → `/qa-case`                     |
| **AI Agent 产品上线** | `/qa-agent` + `/qa-case`                   |
| **迭代测试中**         | `/qa-bug`（发现缺陷时）+ `/qa-report` 日报（每天）      |
| **迭代结束**          | `/qa-report` 阶段报告 + `/qa-team` 准出检查 + 质量评估 |
| **线上出事故**         | `/qa-team` 漏测复盘 + `/qa-bug` 根因分析           |
| **季度汇报**          | `/qa-report` 季度报告 + `/qa-team` 团队效能        |
| **新人入职**          | `/qa-team` 培训计划 + 随 Mentor 使用 `/qa-case`   |
| **周一站会**          | `/qa-report` 周报 + `/qa-team` 团队汇总          |

***

## 技术栈 & 依赖

- **核心依赖**：无。核心 Prompt 纯文本，不涉及外部 API、数据库、网络请求
- **可选依赖**：`ci/run_llm_eval.py` 评测脚本需要外部 LLM API（DeepSeek / OpenRouter / Kimi），需自行配置 API Key（仅环境变量，不写入文件）。不使用 CI 评测则无需任何外部依赖
- **平台适配**：Claude Code / OpenCode / GitHub Copilot / OpenAI Codex CLI / Cursor（见[安装说明](#安装)），可上架 ClawHub / SkillHub
- **许可证**：MIT — 可自由使用、修改、分发

***

## 安全与隐私声明

使用本技能前，请了解以下关键信息：

### 数据持久化
- 本技能的**记忆模块**（`memory/`）会将以下测试数据**持久化到本地文件系统**（`memory/data/products/` 目录下）：测试用例、缺陷分析、评审记录、测试报告、团队数据、探索笔记
- **持久化的前提**：每次写入前 AI **都会先询问你确认**，只有在你确认后才写入本地文件；你拒绝则跳过，本次输出不落盘
- 所有数据**仅本地存储**：不自动上传到外部，仅注入当前对话上下文供本次任务使用，不发送给任何第三方服务

### 需要你确认的操作（均为确认后才执行）
- 记忆写入：每次写入前 AI 会询问你是否确认持久化
- 版本清理：AI 会询问是否删除历史版本文件（默认保留最近 5 个版本）
- 规范沉淀：自动提取的经验教训会先征求你的同意再写入

### 历史记忆加载
- 每次任务启动时，AI 会**先询问你是否加载该模块的历史记忆**，你确认后才扫描并读取 `memory/data/products/` 下的历史数据；你拒绝则按首次使用处理，不会读取任何历史文件

### 注意事项
- ❗ **不要**在输入中粘贴真实的生产环境凭证、支付标识、客户个人信息或敏感截图，除非你的团队已明确批准本地留存
- ❗ `ci/run_llm_eval.py` 评测脚本会连接外部 LLM API（DeepSeek / OpenRouter / Kimi），请确保运行前使用**脱敏**的评测数据
- ❗ 上传文件给 AI 时，内容会出现在生成的报告/用例中——请确保不包含未脱敏的敏感信息
- ✅ 如需重置或清理记忆数据，删除对应产品目录下的 `memory/data/products/` 内容即可

### 数据保留
- 记忆数据长期保留在本地，直到你手动删除
- 历史版本文件默认保留最近 5 个，更早的会在合并快照后归档（数据保留在 `latest.json` 中）
- 不涉及云端同步或第三方数据共享

***

## 贡献 & 反馈

本项目由 QA 团队维护，欢迎通过以下方式参与：

- **使用反馈**：在使用中遇到问题或有改进建议，直接提 Issue
- **行业模板贡献**：如果你的行业（如医疗、教育、物联网）有专属的合规标准或角色配置，欢迎提交到 `team/` 目录
- **版本迭代**：遵循 [`docs/version-policy.md`](./docs/version-policy.md) 中的治理规范

***

## 版本

当前版本：**v1.6.1**

详见 [`docs/CHANGELOG.md`](./docs/CHANGELOG.md)

***

**qa-team-skills** — 让测试团队拥有统一的 AI 辅助标准，不做各自为政的 Prompt 孤岛。
