---
name: log-analyzer
description: 读取并分析 Whimread APP 上报的客户端日志。此 skill 用于从 PostgreSQL 数据库中获取 APP 上报的日志数据，进行 Bug 检测、错误统计、趋势分析和配置问题诊断等全面分析。当用户请求查看日志、分析日志、检查APP错误、诊断问题或查看日志趋势时触发此 skill。
---

# Log Analyzer - APP 日志分析

## 概述

从 PostgreSQL 数据库中读取 Whimread Flutter APP 上报的客户端日志（`client_logs` 表），进行全面的 Bug 检测、错误统计、趋势分析和问题诊断。提供结构化的分析报告和可操作的建议。

## 触发场景

当用户提出以下请求时使用此 skill：
- "查看日志"、"分析日志"、"检查日志"
- "APP 有什么 bug"、"有没有报错"
- "日志趋势"、"日志统计"
- "检查 [特定模块] 的问题"（如 AI、网络、数据库等）
- "清空日志"、"删除日志"

## 分析流程

### Step 1: 获取日志概览

通过 Docker 执行 psql 查询，获取日志基础统计信息：

```bash
docker exec novel_builder-postgres-1 psql -U novel_user -d novel_db -c "SELECT COUNT(*) as total, MIN(received_at) as earliest, MAX(received_at) as latest FROM client_logs;"
```

如果日志总数为 0，直接告知用户无日志数据，结束分析。

### Step 2: 多维度统计

并行执行以下统计查询：

1. **按级别统计**: `SELECT level, COUNT(*) FROM client_logs GROUP BY level ORDER BY count DESC;`
2. **按分类统计**: `SELECT category, COUNT(*) FROM client_logs GROUP BY category ORDER BY count DESC;`
3. **按小时趋势**: `SELECT DATE_TRUNC('hour', received_at) as hour, COUNT(*) FROM client_logs GROUP BY hour ORDER BY hour;`
4. **高频重复日志**: `SELECT message, COUNT(*) FROM client_logs GROUP BY message HAVING COUNT(*) > 3 ORDER BY count DESC;`

> 注意：level 字段查询时需兼容 `warn` 和 `warning` 两个值，使用 `WHERE level IN ('warn', 'warning')`。

### Step 3: 错误与异常分析

1. 获取所有 error 级别日志（含 stack_trace）:
   ```bash
   docker exec novel_builder-postgres-1 psql -U novel_user -d novel_db -c "SELECT level, category, message, stack_trace, timestamp, received_at FROM client_logs WHERE level = 'error' ORDER BY received_at DESC;"
   ```

2. 获取所有 warning 级别日志:
   ```bash
   docker exec novel_builder-postgres-1 psql -U novel_user -d novel_db -c "SELECT level, category, message, timestamp, received_at FROM client_logs WHERE level IN ('warn', 'warning') ORDER BY received_at DESC;"
   ```

3. 获取带堆栈信息的日志:
   ```bash
   docker exec novel_builder-postgres-1 psql -U novel_user -d novel_db -c "SELECT level, category, message, stack_trace, timestamp FROM client_logs WHERE stack_trace IS NOT NULL AND stack_trace != '' ORDER BY received_at DESC;"
   ```

### Step 4: Bug 模式检测

根据 `references/log_system_reference.md` 中的已知 Bug 模式，检查以下问题：

| 检测项 | 检测方法 | 严重程度 |
|--------|---------|---------|
| warn/warning 级别不一致 | 查询 level 同时包含 `warn` 和 `warning` | 中 |
| LLM contentLength=0 | 搜索 ai 分类中 `contentLength=0` 的日志 | 高 |
| DSL Engine 配置缺失 | 搜索 `Hermes Agent 错误` 和 `DSL Engine 配置不完整` 关联日志 | 中 |
| 条件短路全部 false | 搜索 `条件短路求值触发` 和 `节点被 skip` 日志 | 中 |
| 日志洪泛 | 检查高频重复日志（同 message 出现 >10 次） | 低-高 |
| 异常堆栈 | 检查 stack_trace 非空的日志 | 高 |

### Step 5: 生成分析报告

输出格式：

```markdown
## 📊 日志分析报告

### 基本信息
| 指标 | 数值 |
|------|------|
| 总日志数 | X |
| 时间范围 | YYYY-MM-DD HH:MM ~ YYYY-MM-DD HH:MM |
| 错误率 | X% |

### 级别分布
（表格或简要描述）

### 发现的问题
按严重程度排序，每个问题包含：
- **问题描述**
- **相关日志**（引用具体日志内容）
- **严重程度**（🔴 高 / 🟡 中 / 🟢 低）
- **建议修复方向**
```

## 特殊操作

### 清空日志

当用户请求清空日志时：

```bash
docker exec novel_builder-postgres-1 psql -U novel_user -d novel_db -c "TRUNCATE TABLE client_logs RESTART IDENTITY;"
```

执行后确认：`SELECT COUNT(*) FROM client_logs;` 确保结果为 0。

### 按模块分析

当用户指定特定模块时，按 category 过滤。支持模块名与 category key 的映射：

| 用户可能说的 | category 值 |
|-------------|-------------|
| AI、AI功能、LLM、智能 | ai |
| 网络、请求、API | network |
| 数据库、本地存储 | database |
| 界面、UI、页面 | ui |
| 缓存、章节缓存 | cache |
| 语音、TTS | tts |
| 角色、人物 | character |
| 备份、导入导出 | backup |

```bash
docker exec novel_builder-postgres-1 psql -U novel_user -d novel_db -c "SELECT level, message, timestamp FROM client_logs WHERE category = '<category_key>' ORDER BY received_at DESC LIMIT 50;"
```

### 按时间范围分析

支持自然语言时间范围，转换为 SQL 条件：

| 用户说法 | SQL 条件 |
|---------|---------|
| 最近1小时 | `received_at >= NOW() - INTERVAL '1 hour'` |
| 今天 | `DATE(received_at) = CURRENT_DATE` |
| 最近24小时 | `received_at >= NOW() - INTERVAL '24 hours'` |
| 最近7天 | `received_at >= NOW() - INTERVAL '7 days'` |

## 资源

### references/

- `log_system_reference.md` — 数据库表结构、日志级别/分类定义、API 规格、常用 SQL 查询模板、已知 Bug 模式。在需要查看具体字段定义、SQL 模板或 Bug 模式细节时加载此文件。
