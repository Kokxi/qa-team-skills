# /qa 意图匹配规则

## 单步匹配

| 用户说… | 解析为 | 路由到 |
|---------|--------|--------|
| "评审/分析这个需求" | 单步-需求评审 | `/qa-prd` |
| "设计/出测试用例" | 单步-用例设计 | `/qa-case` |
| "分析/定位这个 Bug" | 单步-缺陷分析 | `/qa-bug` |
| "生成/出一份报告" | 单步-报告生成 | `/qa-report` |
| "团队/进度/产出/效能" | 单步-团队管理 | `/qa-team` |
| "测试这个 Agent/AI" | 单步-Agent 测试 | `/qa-agent` |

## 多步匹配

| 用户说… | 解析为 | 步骤序列 |
|---------|--------|---------|
| "先评审再出用例" | 多步-评审→用例 | `prd` → `case` |
| "全量回归并出报告" | 多步-用例→执行→报告 | `case` → `report` |
| "分析缺陷并出团队报告" | 多步-缺陷→团队 | `bug` → `report` 或 `bug` → `team` |
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

| 触发时机 | 写入路径 | 规范类型 |
|---------|---------|---------|
| `/qa-bug` 发现共性根因 | `data/products/{module}/standards.json` | `lession_learned` 或 `checklist` |
| `/qa-team` 漏测复盘输出预防措施 | `data/products/{module}/standards.json` | `checklist` |

写入前检查同 module 同内容的条目是否已存在，避免重复沉淀。
