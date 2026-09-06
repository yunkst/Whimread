#!/usr/bin/env dart

import 'dart:io';

/// 自动化生成 API 客户端代码的脚本
///
/// 使用方式：
/// 1. 确保 openapi-generator-cli 已安装
///    npm install -g @openapitools/openapi-generator-cli
///
/// 2. 确保后端服务运行在 localhost:3800
///
/// 3. 运行此脚本：
///    dart run tool/generate_api.dart
///
/// 4. 运行 flutter pub get 安装生成的依赖

Future<void> main() async {
  stdout.writeln('🚀 开始生成 API 客户端代码...\n');

  // 检测操作系统并选择正确的命令
  final isWindows = Platform.isWindows;
  final generatorCmd =
      isWindows ? 'openapi-generator-cli.cmd' : 'openapi-generator-cli';

  // 检查 openapi-generator-cli 是否安装
  stdout.writeln('📋 检查 openapi-generator-cli 是否已安装...');
  final checkResult = await Process.run(generatorCmd, ['version']);
  if (checkResult.exitCode != 0) {
    stdout.writeln('❌ openapi-generator-cli 未安装');
    stdout.writeln('请运行: npm install -g @openapitools/openapi-generator-cli');
    exit(1);
  }
  stdout.writeln('✅ openapi-generator-cli 已安装\n');

  // 检查后端服务是否运行
  stdout.writeln('📋 检查后端服务 (localhost:3800) 是否运行...');
  try {
    final socket =
        await Socket.connect('localhost', 3800, timeout: Duration(seconds: 3));
    socket.destroy();
    stdout.writeln('✅ 后端服务运行正常\n');
  } catch (e) {
    stdout.writeln('❌ 无法连接到后端服务 localhost:3800');
    stdout.writeln('请先启动后端服务');
    exit(1);
  }

  // 删除旧的生成代码
  final generatedDir = Directory('generated/api');
  if (await generatedDir.exists()) {
    stdout.writeln('🗑️  删除旧的生成代码...');
    await generatedDir.delete(recursive: true);
    stdout.writeln('✅ 删除完成\n');
  }

  // 运行 openapi-generator
  stdout.writeln('⚙️  运行 openapi-generator-cli...');
  stdout.writeln('   配置文件: openapi-config.yaml');
  stdout.writeln('   输出目录: generated/api\n');

  final generateResult = await Process.run(
    generatorCmd,
    ['generate', '-c', 'openapi-config.yaml'],
  );

  if (generateResult.exitCode != 0) {
    stdout.writeln('❌ 生成失败:');
    stdout.writeln(generateResult.stderr);
    exit(1);
  }

  stdout.writeln(generateResult.stdout);
  stdout.writeln('✅ API 客户端代码生成成功!\n');

  // 步骤 2: 运行 flutter pub get 安装依赖
  stdout.writeln('📦 安装生成的依赖包...');
  try {
    final pubGetResult = await Process.run('flutter', ['pub', 'get'],
        workingDirectory: 'generated/api');
    if (pubGetResult.exitCode != 0) {
      stdout.writeln('❌ pub get 失败，尝试使用 dart pub get...');
      final dartPubGetResult = await Process.run('dart', ['pub', 'get'],
          workingDirectory: 'generated/api');
      if (dartPubGetResult.exitCode != 0) {
        stdout.writeln('❌ dart pub get 也失败:');
        stdout.writeln(dartPubGetResult.stderr);
        stdout.writeln('⚠️  将继续，但可能需要手动安装依赖');
      } else {
        stdout.writeln('✅ dart pub get 安装完成\n');
      }
    } else {
      stdout.writeln('✅ flutter pub get 安装完成\n');
    }
  } catch (e) {
    stdout.writeln('❌ 无法运行 pub get: $e');
    stdout.writeln('⚠️  将继续，但可能需要手动安装依赖');
  }

  // 步骤 3: 运行 build_runner 生成 .g.dart 文件
  stdout.writeln('🔧 生成 built_value .g.dart 文件...');
  try {
    final buildRunnerResult = await Process.run(
      'dart',
      ['pub', 'run', 'build_runner', 'build', '--delete-conflicting-outputs'],
      workingDirectory: 'generated/api',
    );
    if (buildRunnerResult.exitCode != 0) {
      stdout.writeln('❌ build_runner 失败:');
      stdout.writeln(buildRunnerResult.stderr);
      stdout.writeln('⚠️  .g.dart 文件未生成，请手动运行 build_runner');
    } else {
      stdout.writeln('✅ .g.dart 文件生成完成\n');
    }
  } catch (e) {
    stdout.writeln('❌ 无法运行 build_runner: $e');
    stdout.writeln('⚠️  .g.dart 文件未生成，请手动运行 build_runner');
  }

  // 验证 .g.dart 文件是否生成
  final modelDir = Directory('generated/api/lib/src/model');
  if (await modelDir.exists()) {
    final dartFiles = await modelDir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.dart'))
        .toList();

    final gFiles =
        dartFiles.where((file) => file.path.endsWith('.g.dart')).toList();

    stdout.writeln('📊 文件统计:');
    stdout.writeln('   - 模型文件: ${dartFiles.length - gFiles.length}');
    stdout.writeln('   - 生成的 .g.dart 文件: ${gFiles.length}');

    if (gFiles.isEmpty) {
      stdout.writeln('⚠️  警告: 未找到 .g.dart 文件，请手动运行 build_runner');
    }
  }

  // 提示下一步操作
  stdout.writeln('\n🎉 API 客户端生成完成!');
  stdout.writeln('📝 下一步操作:');
  stdout.writeln('1. 查看生成的代码: generated/api/');
  stdout.writeln('2. 使用 ApiServiceWrapper 封装调用');
  stdout.writeln(
      '3. 如果需要，运行: flutter packages pub run build_runner build --delete-conflicting-outputs');
}
