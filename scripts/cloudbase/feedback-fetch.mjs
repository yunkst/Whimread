#!/usr/bin/env node
/**
 * 本地拉取用户反馈 / 崩溃报告 / 客户端日志的分析脚本
 *
 * 用法:
 *   # 列出最近 20 条报告(默认)
 *   FEEDBACK_API_BASE=https://whimread.dazhi.site \
 *   PUBLISH_API_TOKEN=$WHIMREAD_BACKEND_TOKEN \
 *   node scripts/cloudbase/feedback-fetch.mjs
 *
 *   # 查看单条详情(含附带日志,markdown 输出)
 *   node scripts/cloudbase/feedback-fetch.mjs --id 123
 *
 *   # 过滤
 *   node scripts/cloudbase/feedback-fetch.mjs --kind native_crash --status open
 *   node scripts/cloudbase/feedback-fetch.mjs --since 2026-09-01 --until 2026-09-09
 *   node scripts/cloudbase/feedback-fetch.mjs --limit 50 --offset 20
 *
 *   # 拉某设备的流式日志(LogReporterService 批量上报)
 *   node scripts/cloudbase/feedback-fetch.mjs --device <android_id> [--level error] [--since ...]
 *
 * 环境变量:
 *   FEEDBACK_API_BASE   后端地址(默认 https://whimread.dazhi.site)
 *   PUBLISH_API_TOKEN   管理端 token(与 deploy.sh 注入云函数的一致)
 *
 * 输出:markdown,方便直接贴进 issue / 存档。
 */

const args = process.argv.slice(2);
function argOf(name) {
  const i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}
function hasFlag(name) {
  return args.includes(name);
}

const API_BASE = (process.env.FEEDBACK_API_BASE || 'https://whimread.dazhi.site').replace(/\/+$/, '');
const TOKEN = process.env.PUBLISH_API_TOKEN;
if (!TOKEN) {
  console.error('❌ 缺少环境变量 PUBLISH_API_TOKEN(管理端 token)');
  process.exit(1);
}

const ID = argOf('--id');
const KIND = argOf('--kind');
const STATUS = argOf('--status');
const SINCE = argOf('--since');
const UNTIL = argOf('--until');
const LIMIT = argOf('--limit') || '20';
const OFFSET = argOf('--offset') || '0';
const DEVICE = argOf('--device') || argOf('--device_id');
const LEVEL = argOf('--level');

function qs(params) {
  const parts = [];
  for (const [k, v] of Object.entries(params)) {
    if (v !== null && v !== undefined && v !== '') {
      parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(v)}`);
    }
  }
  return parts.length ? `?${parts.join('&')}` : '';
}

async function apiGet(pathname) {
  const res = await fetch(`${API_BASE}${pathname}`, {
    headers: { 'X-API-TOKEN': TOKEN },
  });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new Error(`非 JSON 响应(HTTP ${res.status}): ${text.slice(0, 200)}`);
  }
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} ${json.code || ''} ${json.message || ''}`.trim());
  }
  return json;
}

function fmtTime(v) {
  if (!v) return '-';
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? String(v) : d.toISOString().replace('T', ' ').slice(0, 19);
}

function fmtLogLine(l) {
  const ts = fmtTime(l.ts || l.timestamp);
  const tags = Array.isArray(l.tags) && l.tags.length ? ` [${l.tags.join(',')}]` : '';
  const cat = l.category ? ` (${l.category})` : '';
  const trace = l.stack_trace ? `\n    └─ ${String(l.stack_trace).split('\n').join('\n    │  ')}` : '';
  return `- \`${ts}\` **${(l.level || 'info').toUpperCase()}**${cat}${tags} ${l.message || ''}${trace}`;
}

function printReport(r) {
  console.log(`## #${r.id} ${r.title}`);
  console.log('');
  console.log(`- **kind**: ${r.kind}${r.category ? ` / ${r.category}` : ''}`);
  console.log(`- **status**: ${r.status}`);
  console.log(`- **时间**: ${fmtTime(r.created_at)}`);
  console.log(`- **设备**: ${r.device_model || '-'}`);
  console.log(`- **版本**: ${r.app_version || '-'}`);
  console.log(`- **device_id**: ${r.device_id || '-'}`);
  if (r.contact) console.log(`- **联系方式**: ${r.contact}`);
  if (r.log_count != null) console.log(`- **附带日志**: ${r.log_count} 条`);
  console.log('');
  if (r.description) {
    console.log('### 描述');
    console.log('');
    console.log(r.description);
    console.log('');
  }
  if (r.steps) {
    console.log('### 复现步骤');
    console.log('');
    console.log(r.steps);
    console.log('');
  }
}

async function main() {
  try {
    // 1. 单条详情
    if (ID) {
      const { report, logs } = await apiGet(`/api/v1/feedback/detail${qs({ id: ID })}`);
      printReport(report);
      if (logs && logs.length) {
        console.log(`### 附带日志(${logs.length} 条,按 seq 升序)`);
        console.log('');
        for (const l of logs) console.log(fmtLogLine(l));
      }
      return;
    }

    // 2. 按设备拉流式日志
    if (DEVICE) {
      const { logs, count } = await apiGet(`/api/v1/feedback/logs${qs({
        device_id: DEVICE, since: SINCE, until: UNTIL, level: LEVEL, limit: LIMIT,
      })}`);
      console.log(`# 设备 ${DEVICE} 的流式日志(${count} 条,ts 倒序)`);
      console.log('');
      for (const l of logs || []) console.log(fmtLogLine(l));
      return;
    }

    // 3. 默认:列报告
    const { reports } = await apiGet(`/api/v1/feedback/list${qs({
      kind: KIND, status: STATUS, since: SINCE, until: UNTIL, limit: LIMIT, offset: OFFSET,
    })}`);
    if (!reports || reports.length === 0) {
      console.log('(无匹配的报告)');
      return;
    }
    console.log(`# 反馈报告(共 ${reports.length} 条)`);
    console.log('');
    console.log('| # | kind | 标题 | 版本 | 设备 | 日志 | 状态 | 时间 |');
    console.log('|---|---|---|---|---|---|---|---|');
    for (const r of reports) {
      console.log(
        `| ${r.id} | ${r.kind}${r.category ? '/' + r.category : ''} ` +
        `| ${String(r.title).replace(/\|/g, '\\|').slice(0, 40)} ` +
        `| ${r.app_version || '-'} | ${(r.device_model || '-').slice(0, 24)} ` +
        `| ${r.log_count ?? 0} | ${r.status} | ${fmtTime(r.created_at)} |`,
      );
    }
    console.log('');
    console.log('> 查看详情:`node scripts/cloudbase/feedback-fetch.mjs --id <编号>`');
  } catch (e) {
    console.error(`❌ ${e.message}`);
    process.exit(1);
  }
}

main();