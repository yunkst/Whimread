/**
 * CloudBase PG 客户端(云函数内专用)
 *
 * 实现:链式 Builder 包装 tcb.ExecutePGSql 控制面调用(
 *       common/tcb-admin.js),绕过 SDK 3.18.3 的 app.rdb() / app.mysql()
 *       不支持 PG REST 的问题(spec §12.1)。
 *
 * 调用方契约(与原 stub 一致):
 *   const { data, error } = await db.from('table').select('cols').eq('col', val).single();
 *   const { data, error } = await db.from('table').select('cols').eq('col', val).order('col', { ascending: false }).limit(1).single();
 *   const { error } = await db.from('table').insert({...});
 *   const { error } = await db.from('table').update({...}).eq('col', val);
 *   const { data, error } = await db.from('table').update({...}).eq('col', val).gte('col', val).select('cols');
 *
 * 错误码语义:
 *   - NOT_FOUND    .single() 查询无结果
 *   - PG_SQL_FAILED  PG 报错(列名错、约束冲突、权限拒绝 等)
 *   - NO_CREDS      运行时缺凭据(部署时未注入 TCB_ENV_ID)
 *   - HTTP_ERROR    网络失败 / 控制面 5xx
 *
 * ⚠️ [Skill: cloudbase-code-review] 不在响应里 echo SQL / 凭据;db.from()
 *    返回的对象里 columns 都由调用方显式传入,避免 SELECT * 误伤 RLS / 性能。
 */

'use strict';

const { executePGSql, rowsToObjects } = require('./tcb-admin');

const OP_SELECT = 'select';
const OP_INS = 'insert';
const OP_UPD = 'update';
const OP_DEL = 'delete';

// op -> SQL 模板里的列占位符
function quoteIdent(name) {
    // 简单白名单:字母/数字/下划线/点(支持 schema.table)
    if (!/^[a-zA-Z_][a-zA-Z0-9_.]*$/.test(name)) {
        throw new Error(`Invalid identifier: ${name}`);
    }
    return '"' + name.replace(/"/g, '""') + '"';
}

function buildSelect(qb) {
    const cols = qb._select || '*';
    const where = buildWhere(qb._filters);
    const order = qb._order
        ? ` ORDER BY ${quoteIdent(qb._order.col)} ${qb._order.ascending ? 'ASC' : 'DESC'}`
        : '';
    const limit = qb._limit != null ? ` LIMIT ${parseInt(qb._limit, 10)}` : '';
    return `SELECT ${cols} FROM ${quoteIdent(qb._table)}${where}${order}${limit}`;
}

function buildInsert(qb) {
    const keys = Object.keys(qb._insertData);
    if (keys.length === 0) throw new Error('insert() requires non-empty object');
    const cols = keys.map(quoteIdent).join(', ');
    const placeholders = keys.map((_, i) => `$${i + 1}`).join(', ');
    const values = keys.map((k) => qb._insertData[k]);
    const returning = qb._select
        ? ` RETURNING ${qb._select.split(',').map((c) => quoteIdent(c.trim())).join(', ')}`
        : '';
    return {
        sql: `INSERT INTO ${quoteIdent(qb._table)} (${cols}) VALUES (${placeholders})${returning}`,
        values,
    };
}

function buildUpdate(qb) {
    const keys = Object.keys(qb._updateData);
    if (keys.length === 0) throw new Error('update() requires non-empty object');
    const setClause = keys.map((k, i) => `${quoteIdent(k)} = $${i + 1}`).join(', ');
    const where = buildWhere(qb._filters, keys.length);
    const returning = qb._select ? ` RETURNING ${qb._select.split(',').map((c) => quoteIdent(c.trim())).join(', ')}` : '';
    const values = keys.map((k) => qb._updateData[k]);
    return {
        sql: `UPDATE ${quoteIdent(qb._table)} SET ${setClause}${where}${returning}`,
        values,
    };
}

function buildDelete(qb) {
    const where = buildWhere(qb._filters);
    const returning = qb._select ? ` RETURNING ${qb._select.split(',').map((c) => quoteIdent(c.trim())).join(', ')}` : '';
    return `DELETE FROM ${quoteIdent(qb._table)}${where}${returning}`;
}

function buildWhere(filters, valueOffset = 0) {
    if (!filters || filters.length === 0) return '';
    // 第一遍:计算每个 filter 起始参数下标(累计前序 IN 的展开数)
    let cursor = 1 + valueOffset;
    const parts = [];
    for (const f of filters) {
        const col = quoteIdent(f.col);
        if (f.op === 'eq')  { parts.push(`${col} = $${cursor}`); cursor += 1; }
        else if (f.op === 'neq') { parts.push(`${col} <> $${cursor}`); cursor += 1; }
        else if (f.op === 'gt')  { parts.push(`${col} > $${cursor}`); cursor += 1; }
        else if (f.op === 'gte') { parts.push(`${col} >= $${cursor}`); cursor += 1; }
        else if (f.op === 'lt')  { parts.push(`${col} < $${cursor}`); cursor += 1; }
        else if (f.op === 'lte') { parts.push(`${col} <= $${cursor}`); cursor += 1; }
        else if (f.op === 'is')  { parts.push(`${col} IS $${cursor}`); cursor += 1; }
        else if (f.op === 'in') {
            const vals = Array.isArray(f.val) ? f.val : [f.val];
            if (vals.length === 0) throw new Error('IN requires non-empty array');
            const ph = vals.map((_, j) => `$${cursor + j}`).join(', ');
            parts.push(`${col} IN (${ph})`);
            cursor += vals.length;
        }
        else throw new Error(`Unsupported op: ${f.op}`);
    }
    return ' WHERE ' + parts.join(' AND ');
}

function collectValues(filters, baseValues) {
    const values = [...baseValues];
    for (const f of filters) {
        if (f.op === 'in') {
            const vals = Array.isArray(f.val) ? f.val : [f.val];
            values.push(...vals);
        } else {
            values.push(f.val);
        }
    }
    return values;
}

class QueryBuilder {
    constructor(table) {
        this._table = table;
        this._op = null;
        this._select = null;
        this._filters = [];
        this._order = null;
        this._limit = null;
        this._single = false;
        this._insertData = null;
        this._updateData = null;
    }
    select(cols) {
        // select 可在 insert/update 后追加,等价为 RETURNING 子句
        this._op = this._op || OP_SELECT;
        this._select = cols || '*';
        return this;
    }
    eq(col, val) { this._filters.push({op:'eq', col, val}); return this; }
    neq(col, val) { this._filters.push({op:'neq', col, val}); return this; }
    gt(col, val) { this._filters.push({op:'gt', col, val}); return this; }
    gte(col, val) { this._filters.push({op:'gte', col, val}); return this; }
    lt(col, val) { this._filters.push({op:'lt', col, val}); return this; }
    lte(col, val) { this._filters.push({op:'lte', col, val}); return this; }
    is(col, val) { this._filters.push({op:'is', col, val}); return this; }
    in(col, val) { this._filters.push({op:'in', col, val}); return this; }
    order(col, opts = {}) {
        this._order = { col, ascending: opts.ascending !== false };
        return this;
    }
    limit(n) { this._limit = n; return this; }
    range(_from, _to) {
        // 简化:range(from, to) ≈ limit(to - from + 1) offset from
        // 当前调用方未使用 range,先抛错提示
        throw new Error('range() not implemented in this builder');
    }
    single() { this._single = true; return this; }
    insert(data) {
        this._op = OP_INS;
        this._insertData = data;
        return this;
    }
    update(data) {
        this._op = OP_UPD;
        this._updateData = data;
        return this;
    }
    delete() {
        this._op = OP_DEL;
        return this;
    }

    /**
     * 把 builder 状态编译成 SQL + values 数组
     * 暴露给测试用
     */
    _compile() {
        if (this._op === null) this._op = OP_SELECT;
        switch (this._op) {
            case OP_SELECT: {
                const sql = buildSelect(this);
                const values = collectValues(this._filters, []);
                return { sql, values };
            }
            case OP_INS: {
                const { sql, values } = buildInsert(this);
                const allValues = collectValues(this._filters, values);
                return { sql, values: allValues };
            }
            case OP_UPD: {
                const { sql, values } = buildUpdate(this);
                const allValues = collectValues(this._filters, values);
                return { sql, values: allValues };
            }
            case OP_DEL: {
                const sql = buildDelete(this);
                const values = collectValues(this._filters, []);
                return { sql, values };
            }
            default:
                throw new Error(`Unknown op: ${this._op}`);
        }
    }

    async _execute() {
        const { sql, values } = this._compile();
        const parameterized = values.length > 0
            ? sql.replace(/\$(\d+)/g, (_, n) => {
                const i = parseInt(n, 10) - 1;
                const v = values[i];
                if (v === null || v === undefined) return 'NULL';
                if (typeof v === 'number') return String(v);
                if (typeof v === 'boolean') return v ? 'true' : 'false';
                if (v instanceof Date) return `'${v.toISOString()}'`;
                // 字符串 / 对象 → 转义单引号
                return `'${String(v).replace(/'/g, "''")}'`;
            })
            : sql;
        let result;
        try {
            result = await executePGSql(parameterized);
        } catch (e) {
            return { data: null, error: e };
        }

        const isWrite = this._op === OP_INS || this._op === OP_UPD || this._op === OP_DEL;
        const hasReturning = !!this._select && (this._op === OP_INS || this._op === OP_UPD || this._op === OP_DEL);

        if (isWrite && !hasReturning) {
            // UPDATE/DELETE/INSERT 不带 RETURNING:
            // - 0 affectedRows 表示 WHERE 没命中 / INSERT 冲突,语义上是合法的 no-op
            //   (调用方如需区分,可改用 .select() 拿 RETURNING 自己判断)
            // - ExecutePGSql 真正报错会走 catch 抛 Error(已在上方处理)
            // 所以这里一律返回成功,不再合成 NO_AFFECTED_ROWS 错误
            return { data: null, error: null };
        }

        const objects = rowsToObjects(result);
        if (this._single) {
            if (objects.length === 0) {
                return { data: null, error: { code: 'NOT_FOUND', message: 'No rows' } };
            }
            return { data: objects[0], error: null };
        }
        return { data: objects, error: null };
    }

    // 让 await 链式调用正常工作
    then(resolve, reject) {
        return this._execute().then(resolve, reject);
    }
}

class DbFacade {
    from(table) {
        return new QueryBuilder(table);
    }
    /**
     * 暴露 raw SQL 入口(测试 / 复杂查询用)
     * 业务代码请用 db.from(...) 链式 API
     */
    async raw(sql) {
        try {
            const result = await executePGSql(sql);
            return { data: rowsToObjects(result), error: null, raw: result };
        } catch (e) {
            return { data: null, error: e };
        }
    }
}

function getDb(_context) {
    return new DbFacade();
}

module.exports = {
    getDb,
    // 暴露给单测
    _QueryBuilder: QueryBuilder,
};