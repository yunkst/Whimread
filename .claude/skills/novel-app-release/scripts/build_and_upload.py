#!/usr/bin/env python3
"""
Novel App 发布脚本

此脚本自动化执行以下操作：

阶段 1 — 预检（模拟 CI）:
  1.1 flutter analyze --no-fatal-infos
  1.2 flutter test --no-pub test/unit/ test/bug/ test/verification/
  1.3 flutter build apk --release

阶段 2 — 版本识别:
  2.1 从 pubspec.yaml 读取版本信息
  2.2 分析 git diff 生成更新日志

阶段 3 — git 操作:
  3.1 git add .
  3.2 git commit -m "chore: 发布版本 {version}"
  3.3 git tag -a v{version} -m "Release {version}"
  3.4 git push
  3.5 git push origin v{version}

阶段 4 — CI 验证（提交后 10 分钟检查）:
  4.1 等待 10 分钟
  4.2 通过 gh run list 查询最新 CI run 状态
  4.3 报告结果（success / failure / pending）

预检中任何一步失败都会中断发布，因为这意味着 GitHub Actions 也会失败。
可通过 SKIP_PREFLIGHT=1 环境变量跳过预检（不推荐）。
可通过 SKIP_CI_CHECK=1 环境变量跳过 CI 等待和检查（不推荐）。
"""

import os
import re
import subprocess
import sys
import time
from pathlib import Path

# 强制使用 UTF-8 输出（修复 Windows cmd 的 GBK 编码问题）
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass


def get_project_root() -> Path:
    """获取项目根目录（包含此脚本的目录的上五级）"""
    # 脚本位置: .claude/skills/novel-app-release/scripts/build_and_upload.py
    # 需要向上5级到达项目根目录
    return Path(__file__).parent.parent.parent.parent.parent.resolve()


def get_flutter_app_dir(project_root: Path) -> Path:
    """获取 Flutter 应用目录"""
    return project_root / "novel_app"


def get_flutter_version(project_root: Path) -> tuple[str, int]:
    """
    从 pubspec.yaml 读取版本信息

    Returns:
        (version_name, version_code) 例如: ("1.0.1", 2)
    """
    pubspec_path = project_root / "novel_app" / "pubspec.yaml"

    if not pubspec_path.exists():
        raise FileNotFoundError(f"找不到 pubspec.yaml: {pubspec_path}")

    content = pubspec_path.read_text(encoding="utf-8")

    # 解析版本行，格式: version: X.Y.Z+code 或 version: X.Y.Z-preview.N+code
    # version_name 含可选的 SemVer prerelease 后缀（-preview.1 / -alpha / -beta 等），
    # 用于区分发布通道（tag 含 '-' → CI 标记为 prerelease）。
    match = re.search(
        r'^version:\s*(\d+\.\d+\.\d+(?:-\S+)?)\+(\d+)',
        content,
        re.MULTILINE,
    )
    if not match:
        raise ValueError("无法从 pubspec.yaml 解析版本号")

    version_name = match.group(1)
    version_code = int(match.group(2))

    return version_name, version_code


def run_command(args: list[str], cwd: Path, description: str = "") -> tuple[int, str, str]:
    """
    执行命令并处理 Windows 编码问题

    Args:
        args: 命令参数列表
        cwd: 工作目录
        description: 步骤描述（用于日志输出）

    Returns:
        (return_code, stdout, stderr) 元组
    """
    if description:
        print(f"  {description}...")

    result = subprocess.run(
        args,
        cwd=cwd,
        capture_output=True,
        shell=True if os.name == "nt" else False,
    )

    # 尝试 UTF-8 解码，失败则使用 GBK（Windows 中文环境）
    try:
        stdout = result.stdout.decode("utf-8")
    except UnicodeDecodeError:
        try:
            stdout = result.stdout.decode("gbk", errors="ignore")
        except Exception:
            stdout = ""

    try:
        stderr = result.stderr.decode("utf-8")
    except UnicodeDecodeError:
        try:
            stderr = result.stderr.decode("gbk", errors="ignore")
        except Exception:
            stderr = ""

    return result.returncode, stdout, stderr


def run_preflight(project_root: Path) -> bool:
    """
    阶段 1：预检 — 模拟 CI 流程

    运行与 GitHub Actions 完全一致的检查：
    1. flutter analyze --no-fatal-infos
    2. flutter test --no-pub test/unit/ test/bug/ test/verification/
    3. flutter build apk --release

    Returns:
        是否全部通过
    """
    flutter_dir = get_flutter_app_dir(project_root)

    print("=" * 60)
    print("阶段 1/3: 预检（模拟 CI 流程）")
    print("=" * 60)

    # 1.1 flutter analyze
    print("\n  [1.1/3] flutter analyze --no-fatal-infos")
    print("  " + "-" * 40)
    rc, stdout, stderr = run_command(
        ["flutter", "analyze", "--no-fatal-infos"],
        flutter_dir,
    )

    # 打印最后几行（分析结果摘要）
    output_lines = stdout.strip().split("\n") if stdout.strip() else []
    for line in output_lines[-8:]:
        print(f"  {line}")

    if rc != 0:
        print(f"\n  ❌ flutter analyze 失败 (exit code: {rc})")
        print(f"  请修复上述问题后重新运行发布脚本")
        return False
    print("  ✅ flutter analyze 通过")

    # 1.2 flutter test
    # -j 1 串行执行：backup_service_test 等通过全局共享 novel_reader.db 文件
    # 操作的测试在并发下会互相干扰（PathNotFoundException），与 CI 保持一致。
    print("\n  [1.2/3] flutter test --no-pub -j 1 test/unit/ test/bug/ test/verification/")
    print("  " + "-" * 40)
    rc, stdout, stderr = run_command(
        ["flutter", "test", "--no-pub", "-j", "1", "test/unit/", "test/bug/", "test/verification/"],
        flutter_dir,
    )

    # 打印最后几行（测试结果摘要）
    output_lines = stdout.strip().split("\n") if stdout.strip() else []
    for line in output_lines[-8:]:
        print(f"  {line}")

    if rc != 0:
        print(f"\n  ❌ flutter test 失败 (exit code: {rc})")
        print(f"  请修复失败的测试后重新运行发布脚本")

        # 尝试找出具体失败的测试
        failed_lines = [l for l in output_lines if "FAILED" in l or "Some tests failed" in l]
        if failed_lines:
            print(f"  失败摘要:")
            for line in failed_lines[:5]:
                print(f"    {line}")

        if stderr:
            # 只打印 stderr 中非 info 级别的错误
            error_lines = [l for l in stderr.split("\n") if "Error" in l or "error" in l]
            if error_lines:
                print(f"  错误详情:")
                for line in error_lines[:5]:
                    print(f"    {line}")
        return False
    print("  ✅ flutter test 通过")

    # 1.3 flutter build apk --release
    print("\n  [1.3/3] flutter build apk --release")
    print("  " + "-" * 40)
    print("  ⏳ 正在构建 Release APK（可能需要几分钟）...")
    rc, stdout, stderr = run_command(
        ["flutter", "build", "apk", "--release"],
        flutter_dir,
    )

    # 打印最后几行
    output_lines = stdout.strip().split("\n") if stdout.strip() else []
    for line in output_lines[-5:]:
        print(f"  {line}")

    if rc != 0:
        print(f"\n  ❌ flutter build apk --release 失败 (exit code: {rc})")
        print(f"  请修复构建错误后重新运行发布脚本")
        if stderr:
            # 打印 stderr 中关键的错误行
            error_lines = [l for l in stderr.split("\n") if "Error" in l or "error" in l or "FAILURE" in l]
            if error_lines:
                print(f"  错误详情:")
                for line in error_lines[:10]:
                    print(f"    {line}")
            else:
                print(f"  stderr (前500字符): {stderr[:500]}")
        return False
    print("  ✅ flutter build apk --release 通过")

    print("\n" + "=" * 60)
    print("✅ 预检全部通过 — 本地验证与 CI 一致，可以安全发布")
    print("=" * 60)
    return True


def _find_previous_tag(project_root: Path) -> str | None:
    """
    找到最近一个发布 tag（vX.Y.Z 格式）。

    Returns:
        tag 名（如 "v1.9.1"），没有则返回 None
    """
    returncode, stdout, _ = run_command(
        ["git", "tag", "-l", "v[0-9]*.[0-9]*.[0-9]*", "--sort=-version:refname"],
        project_root,
    )
    if returncode != 0 or not stdout.strip():
        return None
    tags = [t.strip() for t in stdout.strip().split("\n") if t.strip()]
    # 第一个就是最新 tag
    return tags[0] if tags else None


def _get_commits_since_tag(project_root: Path, since_tag: str) -> list[str]:
    """
    获取 since_tag 之后到 HEAD 的所有 commit subject（一行一条）。

    Returns:
        commit subject 列表
    """
    returncode, stdout, _ = run_command(
        ["git", "log", "--no-merges", "--pretty=format:%s", f"{since_tag}..HEAD"],
        project_root,
    )
    if returncode != 0 or not stdout.strip():
        return []
    return [s.strip() for s in stdout.strip().split("\n") if s.strip()]


# Conventional Commits 前缀 → 分类
_CC_CATEGORIES: dict[str, str] = {
    "feat": "✨ 新功能",
    "fix": "🐛 修复",
    "perf": "⚡ 性能优化",
    "refactor": "♻️ 重构",
    "docs": "📚 文档",
    "test": "✅ 测试",
    "ci": "👷 CI/CD",
}

# novel_app 路径前缀 → 模块中文名（按匹配优先级排序）
_MODULE_PATTERNS: list[tuple[str, str]] = [
    ("lib/screens/", "界面"),
    ("lib/widgets/", "组件"),
    ("lib/services/", "服务层"),
    ("lib/repositories/", "数据访问层"),
    ("lib/core/providers/", "状态管理"),
    ("lib/controllers/", "控制器"),
    ("lib/core/", "核心"),
    ("lib/models/", "数据模型"),
    ("lib/utils/", "工具类"),
    ("lib/mixins/", "Mixin"),
    ("lib/extensions/", "扩展"),
]


def _parse_commit_subject(subject: str) -> tuple[str, str] | None:
    """
    解析一条 commit subject，返回 (category_key, description) 或 None（表示应跳过）。

    支持的格式：
      - feat: xxx
      - fix(scope): xxx
      - ✨ feat(scope): xxx   (带 emoji 前缀)
      - feat：xxx              (中文冒号)

    也会匹配无前缀但有实际内容的中文描述。
    """
    import re

    # 去掉行首 emoji（如 ✨ 🐛 等）
    cleaned = re.sub(r"^[^\w\s#]\s*", "", subject).strip()

    # 跳过发布 commit（chore: 发布版本 X.Y.Z / chore(release): ...）
    if re.match(r"chore(?:\([^)]*\))?\s*[:：]\s*(?:发布版本|发布 app|release)", cleaned, re.IGNORECASE):
        return None

    # 匹配 conventional commit 前缀
    m = re.match(r"^(\w+)(?:\([^)]*\))?\s*[:：]\s*(.+)$", cleaned)
    if m:
        prefix = m.group(1).lower()
        desc = m.group(2).strip()
        if prefix in _CC_CATEGORIES:
            return (prefix, desc)
        # chore / build / style 不写入 changelog
        if prefix in ("chore", "build", "style"):
            return None
        # 未知前缀但描述不为空 → 归入"其他"
        if desc:
            return ("other", desc)
        return None

    # 无前缀：如果内容是中文或有一定长度，也纳入"其他"
    if len(cleaned) >= 4 and not cleaned.startswith("Merge") and not cleaned.startswith("Revert"):
        return ("other", cleaned)

    return None


def _classify_module(file_path: str) -> str | None:
    """
    将文件路径归类到模块中文名。

    只关注 novel_app/ 下的 .dart 代码文件，其余（.claude/、.md、配置等）返回 None。
    """
    if not file_path.startswith("novel_app/"):
        return None
    if not file_path.endswith(".dart"):
        return None
    for prefix, label in _MODULE_PATTERNS:
        if prefix in file_path:
            return label
    if "novel_app/test/" in file_path:
        return "测试"
    return None


def _get_workdir_changes(project_root: Path) -> dict[str, dict[str, list[str]]]:
    """
    获取工作区相对 HEAD 的所有代码变更，按模块分组。

    Returns:
        {module: {"added": [basename...], "deleted": [...], "modified": [...]}}
    """
    changes: dict[str, dict[str, list[str]]] = {}

    def _record(module: str, status: str, file_path: str) -> None:
        import os
        basename = os.path.splitext(os.path.basename(file_path))[0]
        changes.setdefault(module, {"added": [], "deleted": [], "modified": []})
        if basename not in changes[module][status]:
            changes[module][status].append(basename)

    # 1. 已跟踪文件的变更（含暂存区 + 工作区）
    rc, stdout, _ = run_command(
        ["git", "diff", "HEAD", "--name-status"],
        project_root,
    )
    if rc == 0 and stdout.strip():
        for line in stdout.strip().split("\n"):
            if not line.strip():
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            status_code, file_path = parts[0], parts[-1]
            module = _classify_module(file_path)
            if module is None:
                continue
            # status_code 可能是 A / M / D / R100 / C 等
            if status_code.startswith("A"):
                _record(module, "added", file_path)
            elif status_code.startswith("D"):
                _record(module, "deleted", file_path)
            elif status_code.startswith("R"):
                # 重命名视为删除旧 + 新增新（file_path 已是新名）
                _record(module, "added", file_path)
            else:
                _record(module, "modified", file_path)

    # 2. 未跟踪文件（视为新增）
    rc2, stdout2, _ = run_command(
        ["git", "ls-files", "--others", "--exclude-standard"],
        project_root,
    )
    if rc2 == 0 and stdout2.strip():
        for line in stdout2.strip().split("\n"):
            line = line.strip()
            if not line:
                continue
            module = _classify_module(line)
            if module is None:
                continue
            _record(module, "added", line)

    return changes


def _workdir_to_entries(
    changes: dict[str, dict[str, list[str]]],
) -> dict[str, list[str]]:
    """
    将模块化变更转成 changelog 条目（按 Conventional Commits 分类）。

    映射：新增→feat，删除→refactor，修改→other。
    文件名展示：≤3 个全列，>3 个列前 3 + "等 N 个"。
    """
    entries: dict[str, list[str]] = {}

    def _names(items: list[str]) -> str:
        if len(items) <= 3:
            return "、".join(items)
        return f"{'、'.join(items[:3])} 等 {len(items)} 个"

    for module, ops in changes.items():
        added = ops.get("added", [])
        deleted = ops.get("deleted", [])
        modified = ops.get("modified", [])

        if added:
            entries.setdefault("feat", []).append(f"新增{module}（{_names(added)}）")
        if deleted:
            entries.setdefault("refactor", []).append(f"移除{module}（{_names(deleted)}）")
        if modified:
            if len(modified) == 1:
                entries.setdefault("other", []).append(f"优化{module}（{modified[0]}）")
            else:
                entries.setdefault("other", []).append(f"优化{module}（{len(modified)} 个文件）")

    return entries


def analyze_git_changes(project_root: Path) -> str:
    """
    分析 git 变更生成更新日志。

    数据源（按优先级合并，输出合并后的 Markdown）：
    1. commit history：上一个发布 tag 到 HEAD 的所有非 chore commit subject，
       按 Conventional Commits 前缀分类
    2. 工作区 diff：相对 HEAD 的所有代码变更（新增/删除/修改），
       按模块路径分组，新增→feat，删除→refactor，修改→other

    合并规则：
    - 任一数据源有内容即输出
    - 两者都有时，commit 条目在前，工作区变更追加在后（同一分类内合并）
    - 都为空时降级为 "Bug 修复和性能优化"

    Args:
        project_root: 项目根目录

    Returns:
        生成的更新日志（Markdown 文本）
    """
    print("正在分析代码变更...")

    # ========== 数据源 1: commit history ==========
    commit_grouped: dict[str, list[str]] = {}
    prev_tag = _find_previous_tag(project_root)

    if prev_tag:
        print(f"  上一个发布 tag: {prev_tag}")
        commits = _get_commits_since_tag(project_root, prev_tag)
    else:
        print("  未找到上一个发布 tag，获取最近 50 条 commit")
        rc, stdout, _ = run_command(
            ["git", "log", "--no-merges", "--pretty=format:%s", "-50"],
            project_root,
        )
        commits = [s.strip() for s in stdout.strip().split("\n") if s.strip()] if rc == 0 and stdout.strip() else []

    for subject in commits:
        parsed = _parse_commit_subject(subject)
        if parsed is None:
            continue
        cat, desc = parsed
        commit_grouped.setdefault(cat, []).append(desc)

    # commit 条目去重
    for cat in commit_grouped:
        seen, unique = set(), []
        for d in commit_grouped[cat]:
            if d not in seen:
                seen.add(d)
                unique.append(d)
        commit_grouped[cat] = unique

    # ========== 数据源 2: 工作区 diff ==========
    workdir_changes = _get_workdir_changes(project_root)
    workdir_grouped = _workdir_to_entries(workdir_changes) if workdir_changes else {}

    has_commits = any(commit_grouped.values())
    has_workdir = any(workdir_grouped.values())

    if not has_commits and not has_workdir:
        print("  未找到有效 commit 或工作区改动，使用默认更新日志")
        return "Bug 修复和性能优化"

    # ========== 合并输出 ==========
    category_order = ["feat", "fix", "perf", "refactor", "docs", "test", "ci", "other"]
    category_labels = {**_CC_CATEGORIES, "other": "🔧 其他"}

    # 合并每个分类：commit 条目优先（语义更精准），工作区条目补充在后
    merged: dict[str, list[str]] = {}
    for cat in category_order:
        items = commit_grouped.get(cat, []) + workdir_grouped.get(cat, [])
        if items:
            merged[cat] = items

    if has_workdir and not has_commits:
        total_files = sum(
            len(ops["added"]) + len(ops["deleted"]) + len(ops["modified"])
            for ops in workdir_changes.values()
        )
        print(f"  工作区有 {len(workdir_changes)} 个模块、共 {total_files} 个文件未提交")
    elif has_workdir and has_commits:
        print(f"  工作区另有未提交改动，将作为补充合并")

    lines: list[str] = []
    for cat in category_order:
        items = merged.get(cat)
        if not items:
            continue
        label = category_labels.get(cat, "🔧 其他")
        lines.append(f"### {label}")
        for desc in items:
            lines.append(f"- {desc}")
        lines.append("")

    changelog = "\n".join(lines).strip()
    print(f"生成的更新日志:\n{changelog}")
    return changelog


def commit_and_push(project_root: Path, version: str, changelog: str) -> bool:
    """
    阶段 3：提交代码变更到 git，创建 tag，并推送到远程仓库

    Args:
        project_root: 项目根目录
        version: 版本号
        changelog: 更新日志

    Returns:
        是否成功完成所有操作
    """
    tag_name = f"v{version}"
    # commit message 保持简洁（详情在 tag message 里）
    commit_msg = f"chore: 发布版本 {version}"

    print("-" * 50)
    print("正在提交代码变更...")

    try:
        # 1. 添加所有变更文件
        print("  [1/5] 添加变更文件...")
        subprocess.run(
            ["git", "add", "."],
            cwd=project_root,
            capture_output=True,
            shell=True if os.name == "nt" else False,
            check=True,
        )

        # 2. 提交
        print(f"  [2/5] 提交代码 (chore: 发布版本 {version})...")
        result = subprocess.run(
            ["git", "commit", "-m", commit_msg],
            cwd=project_root,
            capture_output=True,
            shell=True if os.name == "nt" else False,
        )

        try:
            stdout = result.stdout.decode("utf-8")
        except UnicodeDecodeError:
            stdout = result.stdout.decode("gbk", errors="ignore")

        if result.returncode == 0:
            print(f"        提交成功!")
        elif "nothing to commit" in stdout.lower():
            print("        没有需要提交的代码变更（仅打 tag）")
        else:
            print(f"        提交失败: {stdout}")
            return False

        # 3. 创建 tag（用临时文件传递 message，避免 Windows shell 多行参数丢失）
        print(f"  [3/5] 创建标签 {tag_name}...")
        tag_message = f"Release {version}\n\n{changelog}"
        tag_msg_file = project_root / ".git" / "TAG_EDITMSG_TMP"
        tag_msg_file.write_text(tag_message, encoding="utf-8")
        try:
            tag_result = subprocess.run(
                ["git", "tag", "-a", tag_name, "-F", str(tag_msg_file)],
                cwd=project_root,
                capture_output=True,
                shell=True if os.name == "nt" else False,
            )
        finally:
            # 清理临时文件
            try:
                tag_msg_file.unlink(missing_ok=True)
            except Exception:
                pass

        if tag_result.returncode != 0:
            try:
                tag_stderr = tag_result.stderr.decode("utf-8")
            except UnicodeDecodeError:
                tag_stderr = tag_result.stderr.decode("gbk", errors="ignore")
            if "already exists" in tag_stderr.lower():
                print(f"        标签 {tag_name} 已存在，继续推送")
            else:
                print(f"        创建标签失败: {tag_stderr}")
                return False
        else:
            print(f"        标签创建成功!")

        # 4. 推送 commit 到远程
        print(f"  [4/5] 推送 commit 到远程仓库...")
        # 自动检测 remote 名字（origin / o1 / upstream）
        remote_name = "origin"
        for candidate in ("origin", "o1", "upstream"):
            rc, _, _ = run_command(
                ["git", "remote", "get-url", candidate], project_root
            )
            if rc == 0:
                remote_name = candidate
                break

        push_result = subprocess.run(
            ["git", "push", remote_name],
            cwd=project_root,
            capture_output=True,
            shell=True if os.name == "nt" else False,
        )

        try:
            push_stdout = push_result.stdout.decode("utf-8")
        except UnicodeDecodeError:
            push_stdout = push_result.stdout.decode("gbk", errors="ignore")

        if push_result.returncode == 0:
            print(f"        Commit 推送成功!")
        else:
            print(f"        Commit 推送失败: {push_stdout}")
            return False

        # 5. 推送 tag 到远程
        print(f"  [5/5] 推送标签 {tag_name} 到远程仓库...")
        # 自动检测 remote 名字（o1 或 origin）
        remote_name = "origin"
        for candidate in ("origin", "o1", "upstream"):
            rc, _, _ = run_command(
                ["git", "remote", "get-url", candidate], project_root
            )
            if rc == 0:
                remote_name = candidate
                break

        tag_push_result = subprocess.run(
            ["git", "push", remote_name, tag_name],
            cwd=project_root,
            capture_output=True,
            shell=True if os.name == "nt" else False,
        )

        try:
            tag_push_stdout = tag_push_result.stdout.decode("utf-8")
        except UnicodeDecodeError:
            tag_push_stdout = tag_push_result.stdout.decode("gbk", errors="ignore")

        if tag_push_result.returncode == 0:
            print(f"        标签推送成功!")
        else:
            print(f"        标签推送失败: {tag_push_stdout}")
            return False

        return True

    except subprocess.CalledProcessError as e:
        print(f"Git 命令执行失败: {e}")
        return False
    except Exception as e:
        print(f"发布过程出错: {e}")
        return False


def wait_and_check_ci(project_root: Path, version: str, wait_seconds: int = 600) -> str:
    """
    阶段 4：等待 CI 构建完成并检查状态

    等待 [wait_seconds] 秒（默认 10 分钟）后，
    通过 gh CLI 查询最新 CI run 状态。

    Args:
        project_root: 项目根目录
        version: 版本号
        wait_seconds: 等待秒数（默认 600）

    Returns:
        CI 状态字符串: "success" / "failure" / "pending" / "unknown"
    """
    print("=" * 60)
    print(f"阶段 4/4: 等待 CI 构建 ({wait_seconds // 60} 分钟) 并检查状态")
    print("=" * 60)

    # 1. 倒计时（每 60 秒打印一次进度）
    minutes = wait_seconds // 60
    for remaining_min in range(minutes, 0, -1):
        print(f"  ⏳ 剩余等待时间: {remaining_min} 分钟...")
        time.sleep(60)

    # 2. 检查 gh CLI 是否可用
    rc, _, _ = run_command(["gh", "--version"], project_root)
    if rc != 0:
        print("  ⚠️  gh CLI 未安装，请手动检查 GitHub Actions:")
        print("     https://github.com/yunkst/Whimread/actions")
        return "unknown"

    # 3. 查询最新 run 状态
    print("  📡 正在查询 GitHub Actions 状态...")
    rc, stdout, stderr = run_command(
        ["gh", "run", "list", "--limit", "1", "--json",
         "status,conclusion,name,displayTitle,url,createdAt"],
        project_root,
    )
    if rc != 0:
        print(f"  ⚠️  gh run list 执行失败: {stderr[:200]}")
        print("     请手动检查: https://github.com/yunkst/Whimread/actions")
        return "unknown"

    try:
        import json
        runs = json.loads(stdout) if stdout.strip() else []
    except json.JSONDecodeError:
        print(f"  ⚠️  gh run list 返回非 JSON 数据: {stdout[:200]}")
        return "unknown"

    if not runs:
        print("  ⚠️  未找到 CI run")
        return "unknown"

    run = runs[0]
    status = run.get("status", "unknown")
    conclusion = run.get("conclusion")
    name = run.get("displayTitle") or run.get("name", "unknown")
    url = run.get("url", "")
    created_at = run.get("createdAt", "")

    print(f"  📋 最新 run: {name}")
    print(f"     状态: {status}, 结果: {conclusion}")
    print(f"     时间: {created_at}")
    if url:
        print(f"     链接: {url}")

    # 4. 报告结果
    if status in ("in_progress", "queued", "waiting", "pending", "requested"):
        print(f"\n  🟡 CI 仍在进行中，请稍后手动检查: {url}")
        return "pending"

    if status == "completed":
        if conclusion == "success":
            print("\n  ✅ CI 构建成功！Release 已自动创建")
            return "success"
        elif conclusion == "failure":
            print("\n  ❌ CI 构建失败")
            print(f"     请查看日志: {url}")
            return "failure"
        elif conclusion == "cancelled":
            print("\n  ⚠️  CI 被取消")
            return "failure"
        else:
            print(f"\n  ⚠️  CI 结果未知: {conclusion}")
            return "unknown"

    print(f"\n  ⚠️  CI 状态未知: {status}")
    return "unknown"


def main():
    """主函数"""
    # 获取项目根目录
    project_root = get_project_root()
    print(f"项目根目录: {project_root}")
    print("=" * 60)

    # ============================================================
    # 阶段 1: 预检（模拟 CI）
    # ============================================================
    skip_preflight = os.getenv("SKIP_PREFLIGHT", "").strip() in ("1", "true", "yes", "True", "YES")

    if skip_preflight:
        print("⚠️  SKIP_PREFLIGHT=1，跳过预检阶段")
        print("⚠️  请注意：GitHub Actions 仍会运行同样的检查，如失败则发布不成功")
        print("=" * 60)
    else:
        if not run_preflight(project_root):
            print("\n" + "=" * 60)
            print("❌ 预检失败，发布已中断")
            print("   请修复上述问题后重新运行，或使用 SKIP_PREFLIGHT=1 跳过（不推荐）")
            print("=" * 60)
            sys.exit(1)

    # ============================================================
    # 阶段 2: 版本识别
    # ============================================================
    print("\n" + "=" * 60)
    print("阶段 2/3: 版本识别与变更日志")
    print("=" * 60)

    version, version_code = get_flutter_version(project_root)
    print(f"版本: {version} (version_code: {version_code})")

    changelog_env = os.getenv("CHANGELOG", None)
    if changelog_env:
        changelog = changelog_env
        print(f"使用自定义更新日志: {changelog}")
    else:
        changelog = analyze_git_changes(project_root)
    print(f"更新日志: {changelog}")

    # ============================================================
    # 阶段 3: git 操作
    # ============================================================
    print("\n" + "=" * 60)
    print("阶段 3/3: git commit + tag + push")
    print("=" * 60)

    success = commit_and_push(project_root, version, changelog)

    print("=" * 60)
    if success:
        print("🎉 Git 操作完成，标签已推送到 origin")
        print(f"  版本: {version} (code: {version_code})")
        print(f"  标签: v{version}")
        print(f"  GitHub Actions 正在构建 Release APK...")
    else:
        print("❌ Git 发布失败，请检查上方错误信息")
        sys.exit(1)

    # ============================================================
    # 阶段 4: 等待并检查 CI 状态
    # ============================================================
    skip_ci_check = os.getenv("SKIP_CI_CHECK", "").strip() in ("1", "true", "yes", "True", "YES")

    if skip_ci_check:
        print("\n" + "=" * 60)
        print("⚠️  SKIP_CI_CHECK=1，跳过 CI 等待和检查")
        print(f"   请手动检查: https://github.com/yunkst/Whimread/actions")
        print("=" * 60)
        return

    ci_status = wait_and_check_ci(project_root, version)

    print("=" * 60)
    if ci_status == "success":
        print(f"🎉 发布成功! Release {version} 已上线")
        print(f"  Release 页面: https://github.com/yunkst/Whimread/releases/tag/v{version}")
    elif ci_status == "failure":
        print(f"❌ CI 构建失败，请修复后重新发布")
        print(f"  修复后使用新版本号重新运行发布脚本")
        sys.exit(2)
    elif ci_status == "pending":
        print(f"🟡 CI 仍在构建中")
        print(f"  几分钟后手动检查: https://github.com/yunkst/Whimread/actions")
    else:
        print(f"⚠️  CI 状态未知")
        print(f"  请手动检查: https://github.com/yunkst/Whimread/actions")


if __name__ == "__main__":
    main()
