# 贡献指南

感谢您对 Whimread 项目的关注！我们欢迎所有形式的贡献。

## 📋 目录

- [开发环境设置](#开发环境设置)
- [代码规范](#代码规范)
- [提交规范](#提交规范)
- [Pull Request 流程](#pull-request-流程)
- [问题报告](#问题报告)
- [功能请求](#功能请求)
- [文档贡献](#文档贡献)

## 🛠️ 开发环境设置

### 环境要求
- Flutter SDK 3.0+
- Python 3.11+
- Docker & Docker Compose
- Git

### 本地开发设置

1. **Fork 并克隆项目**
```bash
git clone https://github.com/yunkst/Whimread.git
cd novel_builder
```

2. **设置上游仓库**
```bash
git remote add upstream https://github.com/yunkst/Whimread.git
```

3. **安装依赖**
```bash
# 后端依赖
cd backend
pip install -e .

# 前端依赖
cd ../novel_app
flutter pub get
```

4. **配置环境变量**
```bash
cp .env.example .env
# 编辑 .env 文件，设置必要的环境变量
```

5. **启动开发服务**
```bash
# 启动数据库和后端
docker-compose up -d postgres backend

# 启动 Flutter 应用
cd novel_app
flutter run
```

## 📝 代码规范

### Python 代码（后端）
我们使用以下工具来保持代码质量：

```bash
# 代码质量检查
ruff check .          # 快速检查
pylint app/           # 深度检查
mypy app/             # 类型检查

# 代码格式化
ruff format .         # 自动格式化
isort .               # 导入排序
```

**代码风格要求：**
- 遵循 PEP 8 规范
- 使用 Type Hints
- 函数和类必须有文档字符串
- 最大行长度：88 字符

### Dart 代码（前端）
```bash
# 代码分析
flutter analyze

# 代码格式化
flutter format lib/

# 代码生成（Riverpod）
dart run build_runner build --delete-conflicting-outputs

# 测试
flutter test
```

**代码风格要求：**
- 遵循 Dart 官方代码规范
- 使用 Riverpod 进行状态管理（ConsumerWidget / ConsumerStatefulWidget）
- 遵循 Repository 模式进行数据访问
- 使用 dartdoc 格式注释
- 最大行长度：80 字符
- 有意义的变量和函数命名

### 通用规范
- 使用英文编写注释和提交信息
- 删除无用的代码和注释
- 避免硬编码，使用配置文件
- 保持代码简洁和可读性

## 📋 提交规范

我们使用 [Conventional Commits](https://www.conventionalcommits.org/) 规范：

### 提交格式
```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### 类型说明
- `feat`: 新功能
- `fix`: 修复 bug
- `docs`: 文档更新
- `style`: 代码格式调整（不影响功能）
- `refactor`: 代码重构
- `test`: 测试相关
- `chore`: 构建过程或辅助工具的变动

### 示例
```bash
feat(reader): 添加章节书签功能
fix(crawler): 修复搜索结果解析错误
docs(readme): 更新安装说明
refactor(api): 重构搜索服务接口
```

## 🔄 Pull Request 流程

### 1. 创建分支
```bash
git checkout -b feature/your-feature-name
# 或
git checkout -b fix/your-bug-fix
```

### 2. 开发和测试
- 编写代码并确保通过测试
- 添加必要的测试用例
- 更新相关文档

### 3. 提交代码
```bash
git add .
git commit -m "feat: 添加新功能"
git push origin feature/your-feature-name
```

### 4. 创建 Pull Request
1. 访问 GitHub 项目页面
2. 点击 "New Pull Request"
3. 选择正确的分支
4. 填写 PR 描述模板
5. 等待代码审查

### PR 标题和描述要求
- **标题**：使用 Conventional Commits 格式
- **描述**：
  - 说明这个 PR 解决了什么问题
  - 描述实现的主要变更
  - 相关的 Issue 链接
  - 测试情况和截图（如有）

### 代码审查
- 所有 PR 需要至少一个维护者的审查
- 解决所有审查意见后才能合并
- 确保所有测试通过
- 保持提交历史清晰

## 🐛 问题报告

### 报告 Bug
使用 Issue 模板报告 bug：

**必需信息：**
- 问题描述和重现步骤
- 期望行为 vs 实际行为
- 环境信息（操作系统、应用版本等）
- 相关截图或错误日志
- 最小可重现示例（如有）

### 安全漏洞
如发现安全漏洞，请不要在公开 Issue 中报告，请通过 [Security Advisories](https://github.com/yunkst/Whimread/security/advisories/new) 私下报告。

## 💡 功能请求

### 提出新功能
使用功能请求模板：

**内容要求：**
- 功能描述和使用场景
- 预期效果和用户价值
- 可能的实现思路（如有）
- 相关参考资料

### 功能讨论
- 在提交功能请求前，请先搜索已有 Issue
- 大功能建议先在 Discussions 中讨论
- 考虑功能的复杂性和维护成本

## 📚 文档贡献

### 文档类型
- **API 文档**：接口说明和示例
- **用户指南**：功能使用教程见根 [README.md](README.md) 与 [在线介绍页](https://yunkst.github.io/novel_builder/)
- **开发文档**：架构和实现说明（docs/developer-guide.md）
- **部署文档**：安装和配置指南（docs/deployment.md）

### 文档规范
- 使用 Markdown 格式
- 保持目录结构清晰
- 添加必要的截图和示例
- 保持内容更新和准确性

### 贡献方式
- 直接提交 PR 改进现有文档
- 在 Issue 中报告文档问题
- 翻译文档到其他语言

## 🏆 贡献者认可

我们会在以下方面认可贡献者：
- README 中的贡献者列表
- Release notes 中的致谢
- 项目博客中的贡献者介绍

## 📞 获取帮助

如果您在贡献过程中遇到问题：

- 💬 GitHub Discussions：https://github.com/yunkst/Whimread/discussions
- 🐛 Issues：https://github.com/yunkst/Whimread/issues

## 📜 行为准则

请阅读并遵守我们的 [行为准则](CODE_OF_CONDUCT.md)，营造友好包容的社区环境。

---

再次感谢您的贡献！🎉
