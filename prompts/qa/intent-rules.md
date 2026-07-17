# /qa 意图匹配规则

## 单步匹配

| 用户说… | 解析为 | 路由到 |
|---------|--------|--------|
| "评审/分析这个需求" | 单步-需求评审 | `/qa-prd` |
| "设计/出测试用例" | 单步-用例设计 | `/qa-case` |
| "分析/定位这个 Bug" | 单步-缺陷分析 | `/qa-bug` |
| "生成/出一份报告" | 单步-报告生成 | `/qa-report` |
| "团队管理/团队进度/团队产出/团队效能" | 单步-团队管理 | `/qa-team` |
| "测试这个 Agent/AI" | 单步-Agent 测试 | `/qa-agent` |
| "执行探索性测试/执行探索测试/自由探索/帮我发现未知问题" | 单步-探索性测试 | `/qa-explore` |
| "查看测试趋势/查看质量变化/同比/环比/成长" | **趋势查询** | 读取 summary.json → 输出趋势报告 |

## 多步匹配

| 用户说… | 解析为 | 步骤序列 |
|---------|--------|---------|
| "先评审再出用例" | 多步-评审→用例 | `prd` → `case` |
| "全量回归并出报告" | 多步-用例→执行→报告 | `case` → `report` |
| "分析缺陷并出团队报告" | 多步-缺陷→团队 | `bug` → `report` 或 `bug` → `team` |

## 自动规划匹配（v1.5 新增）

| 用户说… | 场景推断 | 推荐步骤 |
|---------|---------|---------|
| "测一下{模块}" / "回归{模块}" | **有历史数据** → 补用例+缺陷分析+报告 | `case` → `report`（历史缺陷多时追加`bug`） |
| "测一下{模块}" / "回归{模块}" | **无历史数据** → 从需求评审开始 | `prd` → `case` → `report` |
| "看下{模块}质量" / "这个版本怎么样" | **有历史数据** → 出趋势报告 | 读取 summary → 输出趋势 |
| "测试这个功能" | 模块不明确 | 询问具体模块名，再编排 |
| "这个功能测完了" / "测试收尾" | 出报告+准出检查 | `report` → `team`（准出检查） |
| 模糊/无法匹配 | 列出匹配到的指令让用户选择 | — |
| 模糊/未匹配 | 列出匹配到的指令让用户选择 | — |

## 跨会话历史加载规则（/qa Step 0）

每次 `/qa` 启动时，在意图解析之前执行：

```
① 从任务描述中提取 scope（产品/模块）
   示例：
   "对支付接口做回归" → scope = "payment"
   "评审登录功能 PRD" → scope = "login"
   "这个版本质量评估" → 询问用户具体模块

② 扫描路径 data/products/{scope}/
   ├─ 存在 → 加载所有记忆文件
   │   ├─ test-cases/latest.json  → 历史用例概况
   │   ├─ bugs/                   → 历史缺陷概况
   │   ├─ reports/                → 历史报告概况
   │   ├─ standards.json          → 历史规范/checklist
   │   └─ summary.json            → 汇总统计
   │
   └─ 不存在 → 首次使用，标记为 new_product

③ 生成记忆简报注入上下文
```

### 记忆简报对后续步骤的影响

| 当前步骤 | 历史数据如何影响 |
|---------|----------------|
| `/qa-case`（用例设计） | 高频缺陷类型自动转化为新增用例；standards.json 中的 checklist 自动注入 |
| `/qa-bug`（缺陷分析） | 对比历史缺陷，检测复发；参考历史修复建议 |
| `/qa-report`（报告生成） | 同比/环比上轮数据 |
| `/qa-team`（团队管理） | 读取历史缺陷趋势，辅助漏测复盘 |

## 记忆检索规则

| 当前步骤 | 数据路径 | 检索方式 |
|---------|---------|---------|
| `case`（用例设计） | `data/products/{module}/reviews/` | 读取同 module 的最近评审记录，转化问题为用例 |
| `case`（用例设计） | `data/products/{module}/bugs/` | 读取历史缺陷，高频根因自动转化为补充用例 |
| `case`（用例设计） | `data/products/{module}/standards.json` | 读取 checklist，补充到用例中 |
| `bug`（缺陷分析） | `data/products/{module}/bugs/` | 查找同一模块的历史缺陷，辅助根因归类、复发检测 |
| `report`（报告生成） | `data/products/{module}/reports/` | 汇总历史报告做同比/环比 |
| `report`（报告生成） | `data/products/{module}/test-cases/` + `bugs/` | 汇总用例和缺陷数据 |
| `team`（团队管理） | `data/products/{module}/reports/` + `bugs/` | 复用历史数据做趋势分析 |

## 多步数据传递规则

| 步骤序列 | 数据传递方式 |
|---------|-------------|
| `prd` → `case` | 将 `prd` 评审问题清单自动注入 `case` 的"评审问题清单"输入字段 |
| `case` → `bug` | 将 `case` 的用例优先级和模块信息注入 `bug` 的上下文 |
| `prd` → `case` → `report` | `prd` 评审维度 + `case` 用例覆盖 → 生成质量报告 |
| `bug` → `report` | `bug` 的根因分析数据 → 报告缺陷趋势部分 |
| `bug` → `team` | `bug` 的缺陷分类 → 团队漏测复盘 |
| `report` → `team` | `report` 的数据 → 团队效能统计 |

## 规范库沉淀规则

| 触发时机 | 写入路径 | 规范类型 | 确认要求 |
|---------|---------|---------|---------|
| `/qa-bug` 发现共性根因 | `data/products/{module}/standards.json` | `lession_learned` 或 `checklist` | **先询问用户确认后**再写入 |
| `/qa-team` 漏测复盘输出预防措施 | `data/products/{module}/standards.json` | `checklist` | **先询问用户确认后**再写入 |

写入前检查同 module 同内容的条目是否已存在，避免重复沉淀。用户拒绝确认则跳过，不影响其他输出。

## 增量合并规则（写入后执行）

每次 `/qa-case` 或 `/qa-agent` 写入新版本后，必须执行一次 latest.json 合并：

| 步骤 | 操作 |
|------|------|
| ① 读取 | 扫描 `data/products/{module}/test-cases/` 下的全部版本文件 |
| ② 去重 | 同标题+同步骤保留最早版本；同场景更优的保留新版本 |
| ③ 重新编号 | 全部用例统一重新编号（TC001、TC002…） |
| ④ 标记来源 | 每条用例标注 source_version（来自 v1.0 / v1.1 / v1.2） |
| ⑤ 写入 | `data/products/{module}/test-cases/latest.json` |
| ⑥ 更新索引 | 更新 `summary.json` 中的 total_test_cases、coverage_by_type 等 |

## 索引文件维护规则

每次写入后同步更新 `data/products/{module}/summary.json`：

| 触发操作 | 更新字段 |
|---------|---------|
| `/qa-case` 合并 latest.json | test_cases 全部字段 |
| `/qa-bug` 写入 | bugs 全部字段 |
| 规范沉淀 | standards 字段 |
| 任意写入 | last_updated, iteration_count |

summary.json 的完整 Schema 见 `memory/schema/summary.json`。

## 历史缺陷→用例转化规则

当记忆简报显示历史缺陷数据时，按以下规则自动转化：

| 历史缺陷类型 | 用例类型 | 优先级 |
|-------------|---------|--------|
| 并发/竞态 | 安全测试-并发防重 | P0 |
| 超时/回调 | 异常测试-超时补偿 | P0 |
| 边界遗漏 | 边界测试-补充边界值 | P1 |
| 安全/注入 | 安全测试-注入防护 | P0 |
| 配置/环境 | 异常测试-Mock验证 | P1 |

转化规则：
- 同类型的缺陷累计出现 ≥ 2 次 → 必须转化
- 已被 latest.json 覆盖的 → 跳过
- 转化后在简明摘要中标注来源
