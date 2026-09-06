#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
简单的 Flutter 覆盖率分析工具
无需 lcov,直接解析 lcov.info 文件
"""

import re
import sys
from pathlib import Path
from collections import defaultdict

# 设置输出编码为 UTF-8
if sys.platform == 'win32':
    import io
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

def parse_lcov(file_path):
    """解析 lcov.info 文件"""
    data = {
        'files': {},
        'total_lines': 0,
        'covered_lines': 0,
        'total_functions': 0,
        'covered_functions': 0,
    }

    current_file = None
    file_data = {}

    with open(file_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()

            # 新文件开始
            if line.startswith('SF:'):
                if current_file:
                    data['files'][current_file] = file_data
                current_file = line[3:]
                file_data = {
                    'lines': {},
                    'functions': {},
                    'total_lines': 0,
                    'covered_lines': 0,
                }

            # 行数据
            elif line.startswith('DA:'):
                match = re.match(r'DA:(\d+),(\d+)', line)
                if match:
                    line_num = int(match.group(1))
                    hit_count = int(match.group(2))
                    file_data['lines'][line_num] = hit_count
                    file_data['total_lines'] += 1
                    if hit_count > 0:
                        file_data['covered_lines'] += 1

            # 函数数据
            elif line.startswith('FN:'):
                match = re.match(r'FN:(\d+),(.+)', line)
                if match:
                    line_num = int(match.group(1))
                    func_name = match.group(2)
                    file_data['functions'][func_name] = {
                        'line': line_num,
                        'hit': False
                    }
                    data['total_functions'] += 1

            # 函数执行数据
            elif line.startswith('FNDA:'):
                match = re.match(r'FNDA:(\d+),(.+)', line)
                if match:
                    hit_count = int(match.group(1))
                    func_name = match.group(2)
                    if func_name in file_data['functions']:
                        file_data['functions'][func_name]['hit'] = hit_count > 0
                        if hit_count > 0:
                            data['covered_functions'] += 1

            # 文件结束
            elif line.startswith('end_of_record'):
                if current_file:
                    data['files'][current_file] = file_data
                    data['total_lines'] += file_data['total_lines']
                    data['covered_lines'] += file_data['covered_lines']
                current_file = None
                file_data = {}

    return data

def print_summary(data):
    """打印覆盖率摘要"""
    print("\n" + "="*60)
    print("📊 Flutter 测试覆盖率报告")
    print("="*60)

    # 行覆盖率
    if data['total_lines'] > 0:
        line_coverage = (data['covered_lines'] / data['total_lines']) * 100
        print(f"\n✅ 行覆盖率 (Line Coverage):")
        print(f"   {data['covered_lines']:,} / {data['total_lines']:,} 行")
        print(f"   {line_coverage:.1f}%")

        # 评级
        if line_coverage >= 80:
            grade = "🟢 优秀"
        elif line_coverage >= 70:
            grade = "🟡 良好"
        elif line_coverage >= 50:
            grade = "🟠 一般"
        else:
            grade = "🔴 需改进"
        print(f"   评级: {grade}")

    # 函数覆盖率
    if data['total_functions'] > 0:
        func_coverage = (data['covered_functions'] / data['total_functions']) * 100
        print(f"\n🎯 函数覆盖率 (Function Coverage):")
        print(f"   {data['covered_functions']:,} / {data['total_functions']:,} 函数")
        print(f"   {func_coverage:.1f}%")

def print_top_files(data, limit=20):
    """打印覆盖率最高和最低的文件"""
    print("\n" + "="*60)
    print("📁 文件覆盖率详情 (Top 20)")
    print("="*60)

    # 计算每个文件的覆盖率
    file_coverages = []
    for file_path, file_data in data['files'].items():
        if file_data['total_lines'] > 0:
            coverage = (file_data['covered_lines'] / file_data['total_lines']) * 100
            file_coverages.append({
                'path': file_path,
                'coverage': coverage,
                'total': file_data['total_lines'],
                'covered': file_data['covered_lines'],
            })

    # 排序
    file_coverages.sort(key=lambda x: x['coverage'], reverse=True)

    # 打印最高覆盖率
    print("\n🟢 覆盖率最高的文件:")
    for i, item in enumerate(file_coverages[:limit//2], 1):
        print(f"   {i:2d}. {item['coverage']:5.1f}% - {item['path']}")
        print(f"       {item['covered']}/{item['total']} 行")

    # 打印最低覆盖率
    print("\n🔴 覆盖率最低的文件 (需要改进):")
    for i, item in enumerate(reversed(file_coverages[-(limit//2):]), 1):
        print(f"   {i:2d}. {item['coverage']:5.1f}% - {item['path']}")
        print(f"       {item['covered']}/{item['total']} 行")

def print_module_breakdown(data):
    """按模块统计覆盖率"""
    print("\n" + "="*60)
    print("📦 模块覆盖率统计")
    print("="*60)

    modules = defaultdict(lambda: {'total': 0, 'covered': 0})

    for file_path, file_data in data['files'].items():
        # 提取模块名 (lib/services/xxx.dart -> services)
        if 'lib/' in file_path:
            parts = file_path.split('lib/')[1].split('/')
            if len(parts) > 1:
                module = parts[0]  # services, widgets, screens 等
                modules[module]['total'] += file_data['total_lines']
                modules[module]['covered'] += file_data['covered_lines']

    # 打印模块统计
    module_list = []
    for module, stats in modules.items():
        if stats['total'] > 0:
            coverage = (stats['covered'] / stats['total']) * 100
            module_list.append({
                'module': module,
                'coverage': coverage,
                'total': stats['total'],
                'covered': stats['covered'],
            })

    module_list.sort(key=lambda x: x['coverage'], reverse=True)

    print(f"\n{'模块':<20} {'覆盖率':>10} {'覆盖/总计':>15}")
    print("-" * 50)
    for item in module_list:
        print(f"{item['module']:<20} {item['coverage']:>9.1f}% {item['covered']:>6}/{item['total']:<6}")

def main():
    """主函数"""
    lcov_file = Path('coverage/lcov.info')

    if not lcov_file.exists():
        print("❌ 错误: coverage/lcov.info 文件不存在")
        print("   请先运行: flutter test --coverage")
        sys.exit(1)

    print("🔍 正在分析覆盖率数据...")

    try:
        data = parse_lcov(lcov_file)
        print_summary(data)
        print_top_files(data)
        print_module_breakdown(data)

        print("\n" + "="*60)
        print("💡 提示:")
        print("   - 安装 lcov 可查看更详细的报告: brew install lcov")
        print("   - 生成 HTML 报告: genhtml coverage/lcov.info -o coverage/html")
        print("   - 在线查看: https://codecov.io")
        print("="*60)

    except Exception as e:
        print(f"❌ 分析失败: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
