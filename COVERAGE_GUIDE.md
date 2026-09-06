# Flutter 测试覆盖率指南

本文档介绍如何在 Whimread 项目中使用代码覆盖率工具。

## 📋 目录

- [快速开始](#快速开始)
- [工具安装](#工具安装)
- [使用方法](#使用方法)
- [CI/CD 集成](#cicd-集成)
- [常见问题](#常见问题)

---

## 🚀 快速开始

### 最简单的方式 (无需额外工具)

```bash
# 1. 运行测试并生成覆盖率数据
flutter test --coverage

# 2. 查看覆盖率数据
cat coverage/lcov.info
```

### 推荐方式 (使用 lcov 生成可视化报告)

```bash
# 1. 运行测试并生成覆盖率
flutter test --coverage

# 2. 生成 HTML 报告
genhtml coverage/lcov.info -o coverage/html

# 3. 在浏览器中打开
open coverage/html/index.html  # macOS
start coverage/html/index.html # Windows
```

### 使用便捷脚本

```bash
# macOS/Linux
./scripts/check_coverage.sh --html

# Windows
.\scripts\check_coverage.bat --html
```

---

## 🛠️ 工具安装

### macOS

```bash
# 安装 lcov (包含 genhtml 和 lcov 命令)
brew install lcov

# 验证安装
lcov --version
genhtml --version
```

### Linux (Ubuntu/Debian)

```bash
# 安装 lcov
sudo apt-get update
sudo apt-get install lcov

# 验证安装
lcov --version
genhtml --version
```

### Windows

1. 下载 lcov for Windows:
   - 官方网站: http://ltp.sourceforge.net/coverage/lcov.php
   - 或使用 WSL (Windows Subsystem for Linux)

2. 或使用 Chocolatey:
   ```powershell
   choco install lcov
   ```

---

## 📖 使用方法

### 1. 运行所有测试并生成覆盖率

```bash
flutter test --coverage
```

**输出**:
- `coverage/lcov.info` - 覆盖率数据文件

### 2. 运行特定测试的覆盖率

```bash
# 只测试某个文件
flutter test test/unit/services/novel_context_service_test.dart --coverage

# 只测试某个目录
flutter test test/unit/services/ --coverage
```

### 3. 生成 HTML 报告

```bash
genhtml coverage/lcov.info -o coverage/html
```

**输出**:
- `coverage/html/index.html` - 可视化覆盖率报告

### 4. 查看覆盖率摘要

```bash
lcov --summary coverage/lcov.info
```

**输出示例**:
```
Summary coverage rate:
  lines......: 82.5% (3284 of 3980 lines)
  functions..: 78.3% (234 of 299 functions)
  branches...: 65.2% (412 of 632 branches)
```

### 5. 使用便捷脚本

#### macOS/Linux

```bash
# 基础用法
./scripts/check_coverage.sh

# 生成 HTML 报告并打开
./scripts/check_coverage.sh --html

# 检查最低覆盖率是否达到 80%
./scripts/check_coverage.sh --min=80
```

#### Windows

```batch
REM 基础用法
check_coverage.bat

REM 生成 HTML 报告并打开
check_coverage.bat --html

REM 检查最低覆盖率 (Windows 脚本不支持自动检查)
check_coverage.bat --min=80
```

---

## 🎨 IDE 集成

### VS Code

#### 方法 1: Coverage Gutters 扩展

1. 安装扩展:
   - `Coverage Gutters` (dbscode.vscode-coverage-gutters)

2. 配置设置:
   ```json
   {
     "coverage-gutters.coverageFileNames": [
       "coverage/lcov.info"
     ],
     "coverage-gutters.coverageBaseDir": "lib"
   }
   ```

3. 使用:
   - 运行 `flutter test --coverage`
   - 点击 "Watch" 按钮
   - 在代码编辑器中查看覆盖率高亮

#### 方法 2: Codecov 扩展

1. 安装扩展:
   - `Codecov` (codecov.codecov-coverage)

2. 上传到 Codecov:
   ```bash
   # 安装 codecov CLI
   bash <(curl -s https://codecov.io/bash)

   # 上传覆盖率
   codecov -f coverage/lcov.info
   ```

### Android Studio / IntelliJ IDEA

1. 打开测试文件
2. 右键点击测试
3. 选择 `Run 'test_name' with Coverage`
4. 查看覆盖率报告

---

## 🔄 CI/CD 集成

### GitHub Actions

创建 `.github/workflows/test.yml`:

```yaml
name: Tests with Coverage

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'

      - name: Install dependencies
        run: flutter pub get

      - name: Run tests with coverage
        run: flutter test --coverage

      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v3
        with:
          files: coverage/lcov.info
          flags: unittests
          name: codecov-umbrella

      - name: Check minimum coverage (optional)
        run: |
          lcov --summary coverage/lcov.info
          # 添加自定义检查逻辑
```

### GitLab CI

创建 `.gitlab-ci.yml`:

```yaml
test:
  image: cirrusci/flutter:stable

  script:
    - flutter pub get
    - flutter test --coverage

  coverage: '/lines\.*:\s(\d+\.\d+)%/'

  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage/cobertura.xml
```

---

## 🎯 覆盖率目标

### 推荐的覆盖率标准

| 代码类型 | 最低覆盖率 | 推荐覆盖率 |
|---------|-----------|-----------|
| **核心业务逻辑** | 80% | 90%+ |
| **工具类/Utils** | 70% | 85%+ |
| **UI Widgets** | 50% | 70%+ |
| **Models** | 60% | 80%+ |
| **整体项目** | 70% | 80%+ |

### 本项目的覆盖率配置

查看 `coverage_config.yaml`:

```yaml
minimum_coverage:
  lines: 70      # 行覆盖率
  functions: 70  # 函数覆盖率
  branches: 60   # 分支覆盖率
```

---

## 📊 覆盖率报告解读

### lcov.info 文件格式

```
SF:lib/services/novel_context_service.dart
DA:1 1    # 第1行被执行1次
DA:2 0    # 第2行未执行
DA:3 5    # 第3行被执行5次
LF:10     # 总共10行
LH:8      # 8行被执行
end_of_record
```

### 覆盖率类型

1. **行覆盖率 (Line Coverage)**: 每一行代码是否被执行
2. **分支覆盖率 (Branch Coverage)**: 每个 if/else 分支是否被执行
3. **函数覆盖率 (Function Coverage)**: 每个函数是否被调用
4. **语句覆盖率 (Statement Coverage)**: 每个语句是否被执行

---

## ❓ 常见问题

### Q1: 覆盖率文件太大怎么办?

**A**: 可以排除不需要测试的文件:

```bash
# 排除生成文件
lcov --remove coverage/lcov.info '**/*.g.dart' -o coverage/lcov.info

# 排除多个文件
lcov --remove coverage/lcov.info \
  '**/*.g.dart' \
  '**/*.freezed.dart' \
  'lib/generated/**' \
  -o coverage/lcov_filtered.info
```

### Q2: 如何查看单个文件的覆盖率?

**A**: 使用 lcov 命令:

```bash
# 提取单个文件的覆盖率
lcov --extract coverage/lcov.info '*/novel_context_service.dart' -o coverage/single_file.info

# 生成该文件的 HTML 报告
genhtml coverage/single_file.info -o coverage/single_file_html
```

### Q3: 覆盖率数据不准确怎么办?

**A**: 检查以下几点:

1. 确保所有测试都通过: `flutter test`
2. 清理旧的覆盖率数据: `rm -rf coverage/`
3. 重新生成: `flutter test --coverage`

### Q4: Windows 上 genhtml 命令不可用?

**A**: 解决方案:

1. 使用 WSL (Windows Subsystem for Linux)
2. 使用在线工具 (Codecov, Coveralls)
3. 只使用 `flutter test --coverage`,不生成 HTML 报告

### Q5: 如何在 CI 中失败当覆盖率未达标?

**A**: 使用脚本中的 `--min` 参数:

```bash
./scripts/check_coverage.sh --min=80
```

或者在 GitHub Actions 中:

```yaml
- name: Check coverage
  run: |
    COVERAGE=$(lcov --summary coverage/lcov.info | grep "lines" | grep -oP '\d+\.\d+(?=%)')
    if (( $(echo "$COVERAGE < 80" | bc -l) )); then
      echo "Coverage $COVERAGE% is below 80%"
      exit 1
    fi
```

---

## 📚 参考资源

- [Flutter 测试文档](https://docs.flutter.dev/cookbook/testing)
- [lcov 官方文档](http://ltp.sourceforge.net/coverage/lcov.php)
- [Codecov 文档](https://docs.codecov.com/)
- [覆盖率最佳实践](https://github.com/giovanni-bussi/covtest)

---

## 🎓 最佳实践

1. **持续监控**: 每次提交都运行覆盖率检查
2. **合理目标**: 不是 100% 覆盖率,而是 70-80% 的有效覆盖
3. **关注核心**: 核心业务逻辑应该有更高的覆盖率
4. **定期审查**: 定期查看覆盖率报告,找出测试盲点
5. **自动化**: 在 CI/CD 中集成覆盖率检查

---

**最后更新**: 2026-01-30
**维护者**: Whimread Team
