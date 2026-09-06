# 常见数据库更新模式

本文档收录 Whimread 项目中常见的数据库更新模式和代码示例。

## 模式 1: 添加单个新列

**场景：** 表已存在，需要添加新字段

```python
def upgrade() -> None:
    op.add_column(
        'scene_comfyui_tasks',
        sa.Column('model_name', sa.String(length=100), nullable=True)
    )

def downgrade() -> None:
    op.drop_column('scene_comfyui_tasks', 'model_name')
```

## 模式 2: 批量添加相同列到多个表

**场景：** 多个表需要添加相同字段（如 model_name）

```python
def upgrade() -> None:
    tables = ['scene_comfyui_tasks', 'scene_comfyui_images']

    for table in tables:
        op.add_column(
            table,
            sa.Column('model_name', sa.String(length=100), nullable=True)
        )

def downgrade() -> None:
    # 回滚时按相反顺序删除
    op.drop_column('scene_comfyui_images', 'model_name')
    op.drop_column('scene_comfyui_tasks', 'model_name')
```

## 模式 3: 添加带默认值的列

**场景：** 新列需要为现有记录提供默认值

```python
def upgrade() -> None:
    op.add_column(
        'users',
        sa.Column('status', sa.String(length=20), nullable=False, server_default='active')
    )

def downgrade() -> None:
    op.drop_column('users', 'status')
```

## 模式 4: 添加外键约束

**场景：** 需要建立表之间的关联关系

```python
def upgrade() -> None:
    op.create_foreign_key(
        'fk_scene_images_task_id',
        'scene_comfyui_images',
        'scene_comfyui_tasks',
        ['task_id'],
        ['task_id']
    )

def downgrade() -> None:
    op.drop_constraint('fk_scene_images_task_id', 'scene_comfyui_images')
```

## 模式 5: 添加索引

**场景：** 查询性能优化，为常用查询字段添加索引

```python
def upgrade() -> None:
    op.create_index(
        'ix_scene_comfyui_tasks_task_id',
        'scene_comfyui_tasks',
        ['task_id'],
        unique=False
    )

def downgrade() -> None:
    op.drop_index('ix_scene_comfyui_tasks_task_id', table_name='scene_comfyui_tasks')
```

## 模式 6: 添加唯一约束

**场景：** 确保字段值唯一性

```python
def upgrade() -> None:
    op.create_unique_constraint(
        'unique_task_prompt',
        'scene_comfyui_tasks',
        ['task_id', 'comfyui_prompt_id']
    )

def downgrade() -> None:
    op.drop_constraint('unique_task_prompt', 'scene_comfyui_tasks')
```

## 模式 7: 修改列属性

**场景：** 改变列的类型、长度或是否可为空

```python
def upgrade() -> None:
    # 增加 varchar 长度
    op.alter_column(
        'scene_comfyui_tasks',
        'task_id',
        existing_type=sa.String(length=255),
        type_=sa.String(length=500)
    )

def downgrade() -> None:
    op.alter_column(
        'scene_comfyui_tasks',
        'task_id',
        existing_type=sa.String(length=500),
        type_=sa.String(length=255)
    )
```

## 模式 8: 创建新表

**场景：** 需要全新的数据表

```python
def upgrade() -> None:
    op.create_table(
        'scene_comfyui_images',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('comfyui_prompt_id', sa.String(length=255), nullable=False),
        sa.Column('images', sa.String(length=5000), nullable=False, server_default='[]'),
        sa.Column('status_fetched', sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('fetched_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()'), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(
        op.f('ix_scene_comfyui_images_comfyui_prompt_id'),
        'scene_comfyui_images',
        ['comfyui_prompt_id'],
        unique=True
    )

def downgrade() -> None:
    op.drop_index(op.f('ix_scene_comfyui_images_comfyui_prompt_id'), table_name='scene_comfyui_images')
    op.drop_table('scene_comfyui_images')
```

## 模式 9: 删除列

**场景：** 移除不再使用的字段

**注意：** 删除前先备份数据！

```python
def upgrade() -> None:
    op.drop_column('table_name', 'deprecated_column')

def downgrade() -> None:
    op.add_column(
        'table_name',
        sa.Column('deprecated_column', sa.String(length=100), nullable=True)
    )
```

## 模式 10: 重命名列

**场景：** 列名需要更清晰的语义

```python
def upgrade() -> None:
    op.alter_column(
        'table_name',
        'old_name',
        new_column_name='new_name'
    )

def downgrade() -> None:
    op.alter_column(
        'table_name',
        'new_name',
        new_column_name='old_name'
    )
```

## 数据迁移模式

### 从旧表迁移数据到新表

```python
def upgrade() -> None:
    # 1. 创建新表
    op.create_table(...)

    # 2. 迁移数据
    op.execute("""
        INSERT INTO new_table (col1, col2)
        SELECT col1, col2
        FROM old_table
    """)

    # 3. 可选：删除旧表或保留备份
    # op.drop_table('old_table')

def downgrade() -> None:
    op.drop_table('new_table')
```

## 常见数据类型映射

| SQLAlchemy 类型 | PostgreSQL 类型 | 说明 |
|----------------|----------------|------|
| `sa.String(length=100)` | VARCHAR(100) | 定长字符串 |
| `sa.Text()` | TEXT | 不限长度文本 |
| `sa.Integer()` | INTEGER | 整数 |
| `sa.BigInteger()` | BIGINT | 大整数 |
| `sa.Boolean()` | BOOLEAN | 布尔值 |
| `sa.DateTime(timezone=True)` | TIMESTAMP WITH TIME ZONE | 时间戳（带时区） |
| `sa.Date()` | DATE | 日期 |
| `sa.Float()` | DOUBLE PRECISION | 浮点数 |
| `sa.Numeric(precision=10, scale=2)` | NUMERIC(10, 2) | 精确数值 |

## 检查清单

执行迁移前确认：

- [ ] 已备份生产数据库
- [ ] 迁移文件语法正确
- [ ] 已实现 `downgrade()` 函数
- [ ] 在开发环境测试过
- [ ] 文档更新了相关变更
- [ ] 通知团队成员即将执行迁移

## 实战示例：SceneComfyUI 模型更新

完整的实际案例，展示如何解决 "column model_name does not exist" 错误。

**问题诊断：**
```bash
# 日志显示错误
psycopg2.errors.UndefinedColumn: column scene_comfyui_tasks.model_name does not exist
```

**解决方案：**

1. 创建迁移：
```bash
docker exec novel_builder-backend-1 alembic revision -m "add_model_name_to_scene_comfyui_tables"
```

2. 编写迁移逻辑：
```python
def upgrade() -> None:
    """添加 model_name 字段到 scene_comfyui_tasks 和 scene_comfyui_images 表"""
    op.add_column(
        'scene_comfyui_tasks',
        sa.Column('model_name', sa.String(length=100), nullable=True)
    )
    op.add_column(
        'scene_comfyui_images',
        sa.Column('model_name', sa.String(length=100), nullable=True)
    )

def downgrade() -> None:
    """回滚：删除 model_name 字段"""
    op.drop_column('scene_comfyui_images', 'model_name')
    op.drop_column('scene_comfyui_tasks', 'model_name')
```

3. 执行迁移：
```bash
docker exec novel_builder-backend-1 alembic upgrade head
```

4. 验证：
```bash
docker exec novel_builder-postgres-1 psql -U novel_user -d novel_db -c "\d scene_comfyui_tasks"
```

5. 重启服务并测试
