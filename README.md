# qa-team-skills

> 将 AI Agent 嵌入软件测试全流程的开源技能包 — 不是替代测试人员，是让测试团队拥有统一的 AI 辅助标准。

[![Version](https://img.shields.io/badge/version-v1.3.0-blue)](./VERSION)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![Platform](https://img.shields.io/badge/platform-Claude%20Code-orange)](https://claude.ai/code)
[![SkillHub](https://img.shields.io/badge/SkillHub-ready-brightgreen)](./SKILL.md)
[![ClawHub](https://img.shields.io/badge/ClawHub-ready-brightgreen)](./SKILL.md)

---

## 为什么有这个项目？

测试团队普遍面临一个困境：**每个人用 AI 的方式不一样，输出的质量不一样**。

同样是需求评审，张三把 PRD 粘贴给 AI 得到 3 个问题，李四用另一种问法得到 15 个——不是需求本身差异大，是每个人的 Prompt 水平差异大。用例设计更是重灾区：有人只写 Happy Path，有人忘了边界值，新人完全不知道该问 AI 什么。团队越大，这个问题越严重。评审会上的精力不是花在"讨论问题"上，而是花在"对齐标准"上。

**qa-team-skills 解决的就是这个问题**：把测试团队最核心的 6 个工作环节——需求评审、用例设计、Agent 专项测试、缺陷分析、报告生成、团队管理——封装成 6 个标准化的 AI 指令。团队成员输入一样的东西，得到一样结构的输出。评审时的讨论对象从"格式对不对"变成了"问题有没有道理"。

---

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

| 层级 | 定义 | 示例 |
|------|------|------|
| **核心层** | 做不到这个，产品就没有存在价值 | 订单能否提交、支付能否成功 |
| **体验层** | 能用，但好不好用 | 错误提示是否清晰、操作步骤是否合理 |
| **增值层** | 锦上添花 | 动画效果、深色模式、社交分享 |

铅笔能不能写字是核心层，握笔舒不舒服是体验层，好不好看是增值层。在 `/qa-case` 中，每条用例同时标注业务分层和优先级——两个维度独立但互补，让测试资源分配不再拍脑袋。

### 4. 通用于任何行业

本技能不绑定安全、金融、ERP 等任何特定行业。核心流程 100% 通用。合规要求是可选输入——只有当你明确提供了行业标准（如 ISO 27001、GDPR、SOX），AI 才会在用例中追加密合检查点。行业配置参考文件（`team/roles.json`、`team/standards.json`）可自由定制。

### 5. 管理者视角：AI 用错了比不用更危险

SKILL.md 中专门有一章「人工校验规则」，不是给 AI 看的——是给人看的。P0 用例必须人工审阅、置信度"中/低"的根因分析必须有第二人复核、自动生成的报告数据必须与原始系统抽样核对。AI 的输出是辅助，最终的测试决策由人做出。

---

## 6 大指令

| 指令 | 做什么 | 适合谁 | 核心亮点 |
|------|--------|--------|----------|
| `/qa-prd` | 需求评审 | 测试工程师、测试经理 | 11 维度系统扫描 + 业务分层建议 + 澄清问题清单 |
| `/qa-case` | 测试用例设计 | 测试工程师 | 6 测试类型 × 9 黑盒方法 + 业务分层，自动交叉匹配 |
| `/qa-agent` | AI 智能体专项测试 | 测试工程师 | 16 维度（含 RAG），覆盖幻觉/偷懒/稳定性/可控性 |
| `/qa-bug` | 缺陷分析 | 测试工程师、开发 | 先评估描述质量 → 再分析根因，标注置信度，支持批量 |
| `/qa-report` | 报告生成 | 测试工程师 | 日报/周报/阶段/季度/专项，支持 API 拉取 Jira/禅道 |
| `/qa-team` | 团队管理 | 测试经理 | 11 项子能力，含进度看板/产出统计/准入准出/质量评估 |

---

## 为什么选择 qa-team-skills？

**如果你是一个测试工程师**：
- 拿到 PRD 不用想"从哪开始审"，粘贴到 `/qa-prd`，11 个维度自动扫描
- 写完用例不用被问"你怎么没考虑边界值"，黑盒方法矩阵自动确保覆盖
- 发现 Bug 不用跟开发来回扯皮，`/qa-bug` 帮你把现象→根因→回归要点一次理清
- 写日报不再是一件头疼的事，`/qa-report` 一段话进去、结构化日报出来

**如果你是一个测试经理**：
- 周一晨会不再靠"口述进度"，`/qa-team` 一键生成看板和趋势
- 团队评审标准统一——所有人用同样的指令、得到同样结构的输出
- 版本能不能发不再靠直觉，准入准出检查 + 版本质量评分有据可查
- 新人上手周期减半——有标准化工具就不用每个人从头教

**如果你是一个研发总监/VP**：
- 每份测试报告都有"30 秒速览"摘要——不需要读完整报告就能了解质量状态
- 季度汇报有数据支撑：缺陷密度、修复率、漏测率趋势一目了然
- 半年后可以回答：引入 AI 辅助后，测试团队效能提升了多少

---

## 快速开始

### 安装

```bash
# 全局安装（推荐，所有项目可用）
cp -r qa-team-skills ~/.claude/skills/

# 项目内安装（仅当前项目）
cp -r qa-team-skills ./.claude/skills/
```

### 使用

```bash
/qa-prd      # 粘贴 PRD → 11 维度评审报告 + 业务分层建议
/qa-case     # 输入需求 → 6 类型 × 9 方法结构化用例
/qa-agent    # 描述 Agent → 16 维度专项测试用例（含 RAG）
/qa-bug      # 粘贴缺陷 → 质量评估 → 根因分析（支持批量）
/qa-report   # 填入数据 → 日报/周报/阶段报告
/qa-team     # 汇总团队数据 → 管理看板/趋势/产出
```

### 示例

**[examples/](./examples/)** 目录包含全部 6 个指令的完整输入输出示例（均来自真实测试场景）：

| 示例 | 指令 | 场景 |
|------|------|------|
| [prd-demo.md](./examples/prd-demo.md) | `/qa-prd` | 订单改价需求评审，11 维度扫描 |
| [login-demo.md](./examples/login-demo.md) | `/qa-case` | 登录功能 35 条用例 × 3 业务层 |
| [case-demo.md](./examples/case-demo.md) | `/qa-case` | 订单改价，评审问题→用例转化 |
| [agent-demo.md](./examples/agent-demo.md) | `/qa-agent` | 智能客服 16 维度，含 RAG |
| [bug-demo.md](./examples/bug-demo.md) | `/qa-bug` | 从被驳回 → 根因定位 + 批量 |
| [report-demo.md](./examples/report-demo.md) | `/qa-report` | 三段话 → 日报/周报/阶段报告 |
| [team-demo.md](./examples/team-demo.md) | `/qa-team` | 迭代末看板/产出/准出 |

---

## 项目结构

```
qa-team-skills/
├── SKILL.md                      # 技能入口：6 指令总览 + 人工校验规则
├── VERSION                       # 当前版本
├── README.md                     # 本文件
├── LICENSE                       # MIT
├── prompts/                      # 6 个指令的 Prompt 定义
│   ├── prd/prompt.md             #   需求评审（11 维度 + 业务分层）
│   ├── case/prompt.md            #   用例设计（9 方法 × 6 类型 + 业务分层）
│   ├── agent/prompt.md           #   Agent 专项（16 维度含 RAG）
│   ├── bug/prompt.md             #   缺陷分析（质量评估 + 根因 + 批量）
│   ├── report/prompt.md          #   报告生成（5 种 + API 拉取）
│   └── team/prompt.md            #   团队管理（11 子能力 + 路由）
├── templates/                    # 输出模板
│   ├── requirement.md            #   通用测试用例模板
│   ├── agent-test.md             #   Agent 专项模板（含中文 Payload）
│   └── error-output.md           #   统一错误格式
├── examples/
│   └── login-demo.md             # 登录功能 35 条用例完整示例
├── team/                         # 行业配置（可选引用）
│   ├── roles.json                #   角色映射
│   └── standards.json            #   合规标准参考
├── ci/
│   ├── validate.sh               # CI 校验脚本
│   └── forbidden.txt             #   禁止词列表
└── docs/
    ├── user-manual.md            # 完整使用手册
    ├── CHANGELOG.md              # 变更日志
    ├── process-integration.md    # 流程嵌入指南
    └── version-policy.md         # 版本治理策略
```

---

## 适用场景

| 场景 | 推荐指令组合 |
|------|-------------|
| **新需求从零开始** | `/qa-prd` → `/qa-case` |
| **AI Agent 产品上线** | `/qa-agent` + `/qa-case` |
| **迭代测试中** | `/qa-bug`（发现缺陷时）+ `/qa-report` 日报（每天） |
| **迭代结束** | `/qa-report` 阶段报告 + `/qa-team` 准出检查 + 质量评估 |
| **线上出事故** | `/qa-team` 漏测复盘 + `/qa-bug` 根因分析 |
| **季度汇报** | `/qa-report` 季度报告 + `/qa-team` 团队效能 |
| **新人入职** | `/qa-team` 培训计划 + 随 Mentor 使用 `/qa-case` |
| **周一站会** | `/qa-report` 周报 + `/qa-team` 团队汇总 |

---

## 搜索关键词

`AI测试` `测试用例生成` `需求评审` `测试报告` `缺陷分析` `测试团队管理` `Claude Code Skill` `AI Agent测试` `黑盒测试方法` `RAG测试` `Claude Skill` `测试自动化` `QA工具` `测试流程` `敏捷测试` `软件测试AI` `智能测试` `测试标准化` `Jira对接` `禅道对接` `AI辅助测试` `测试效能` `ClawHub` `SkillHub` `测试左移` `探索性测试` `测试技能包` `测试工程化`

---

## 技术栈 & 依赖

- **运行时**：Claude Code（Opus 4.7 / 4.8 / Sonnet 4.6 / Haiku 4.5）
- **依赖**：无。纯 Prompt 工程，不涉及外部 API、数据库、网络请求
- **平台适配**：可上架 ClawHub / SkillHub 等技能聚合平台
- **许可证**：MIT — 可自由使用、修改、分发

---

## 贡献 & 反馈

本项目由 QA 团队维护，欢迎通过以下方式参与：
- **使用反馈**：在使用中遇到问题或有改进建议，直接提 Issue
- **行业模板贡献**：如果你的行业（如医疗、教育、物联网）有专属的合规标准或角色配置，欢迎提交到 `team/` 目录
- **版本迭代**：遵循 [`docs/version-policy.md`](./docs/version-policy.md) 中的治理规范

---

## 版本

当前版本：**v1.3.0**

详见 [`docs/CHANGELOG.md`](./docs/CHANGELOG.md)

---

**qa-team-skills** — 让测试团队拥有统一的 AI 辅助标准，不做各自为政的 Prompt 孤岛。
