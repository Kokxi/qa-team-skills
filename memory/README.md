# 记忆模块（Memory Module）

## 定位

记忆模块是 qa-team-skills 的**长期记忆体**，负责在多次迭代间持续沉淀和复用测试资产，让技能越用越好：

- **用例库**：每轮迭代的用例不断累积，按产品模块组织，支持继承和进化
- **缺陷库**：历史缺陷分析结果持久化，支持根因归类、复发检测、趋势分析
- **评审库**：历史需求评审结果，问题清单可跨迭代转化为用例
- **报告库**：历史测试报告，支持同比/环比趋势
- **规范库**：团队测试规范、Checklist、经验教训——从缺陷中自动沉淀

## 架构

```
memory/
├── README.md              ← 本文件：模块说明
├── schema/                 ← 数据模型定义
│   ├── review.json         ← 评审记录模型
│   ├── test-case.json      ← 测试用例模型
│   ├── bug.json            ← 缺陷记录模型
│   ├── report.json         ← 报告记录模型
│   ├── task-session.json   ← 任务会话模型
│   └── standard.json       ← 测试规范模型
└── data/
    └── products/            ← 按产品/模块组织（由 AI 自动创建）
        ├── payment/         ← 支付模块
        │   ├── test-cases/
        │   │   ├── v1.0.json    ← 第一轮迭代用例
        │   │   ├── v1.1.json    ← 第二轮（增量追加）
        │   │   └── latest.json  ← 汇总快照（自动合并去重）
        │   ├── bugs/
        │   │   ├── v1.0.json
        │   │   └── v1.1.json
        │   ├── reviews/
        │   ├── reports/
        │   ├── standards.json   ← 本模块沉淀的规范/checklist
        │   └── summary.json     ← 汇总索引（总用例数/缺陷分布/趋势）
        │
        └── login/           ← 登录模块（同上结构）
            └── ...
```

> `data/` 目录不在版本库中。每个产品模块的目录由 AI 在首次写入时自动创建。

## 数据模型

每个库的 JSON Schema 定义了存储结构。所有库共有以下核心字段：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 唯一标识，格式：`{库前缀}-{日期}-{序号}` |
| `created_at` | string | 创建时间（ISO 8601） |
| `module` | string | 所属产品/模块 |
| `source` | string | 来源 session_id |
| `tags` | string[] | 自定义标签，方便检索 |
| `iteration` | string | 所属迭代版本（如 v1.0、v1.1） |

### 各库特有字段

详见 `schema/` 目录下各 JSON Schema 文件。

## 生命周期

### 跨会话历史加载（/qa Step 0）

每次 `/qa` 任务开始时，先扫描历史：

```
Step 0: 历史加载
├─ 解析 scope = "支付接口"
├─ 扫描 data/products/payment/ 是否存在
│   ├─ 存在 → 读取 summary.json → 生成记忆简报
│   └─ 不存在 → 首次使用，跳过后面的历史步骤
│
└─ 记忆简报注入到后续所有步骤的上下文
```

记忆简报格式详见 `prompts/qa/prompt.md`。

### 增量写入（每个指令步骤完成后）

每步执行完成后，按 module 追加到对应产品目录：

```
输出 → 按 Schema 结构化
     → 定位 data/products/{module}/{库名}/
     → 创建新版本文件（如 v1.2.json）
     → 更新 summary.json（增删统计）
```

### 汇总快照（/qa-case 写入后必执行）

每次 `/qa-case` 或 `/qa-agent` 写入新版本后，必须做一次合并：

```
读取 data/products/payment/test-cases/ 下的全部版本文件
├─ v1.0.json（12 条）← 首次
├─ v1.1.json（+6 条）← 增量
└─ v1.2.json（+5 条）← 本次新增

合并逻辑：
├─ 去重：同标题+同步骤保留最早版本
├─ 优选：同场景更优的用例保留新版本
├─ 警告：连续 2 轮未覆盖的测试类型标记为黄色
├─ 重新编号：TC001 → TC023
└─ 写入 latest.json + 更新 summary.json
```

### 历史缺陷→用例转化

当 `/qa-case` 加载到同模块的历史缺陷数据时，自动将高频缺陷转化为新增用例：

```
历史缺陷：并发扣款 4 次（33%）
  → 新增：并发支付防重测试（安全/P0）

历史缺陷：超时回调 3 次（25%）
  → 新增：网关超时补偿测试（异常/P0）

已被 latest.json 覆盖的缺陷类型 → 跳过
```

### 规范库闭环

当 `/qa-bug` 发现共性根因或 `/qa-team` 做漏测复盘时，自动向规范库沉淀：

```
发现共性根因（如"并发扣款连续3轮出现"）
  → 生成规范条目（category: "lession_learned" 或 "checklist"）
  → 写入 data/products/{module}/standards.json
  → 后续 /qa-case 启动时自动读取，补充到用例中
```

### 清理

| 操作 | 时机 | 说明 |
|------|------|------|
| 创建 | 每次 `/qa` 任务执行 | 自动生成 session_id |
| 写入 | 每个指令步骤完成后 | 按产品模块追加到对应目录 |
| 合并 | 用例/缺陷写入后可选 | 生成 latest.json 快照 |
| 规范沉淀 | 发现共性根因/漏测复盘时 | 自动写入 standards.json |
| 清理 | 手动 | 删除过期版本文件，保留 latest.json |
