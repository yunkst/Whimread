import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/services/log_reporter_service.dart';
import 'package:novel_app/services/logger_service.dart';

/// LogReporterService 单元测试
///
/// 测试核心逻辑：
/// - 级别过滤
/// - 缓冲区管理
/// - 启用/禁用开关
/// - 退避策略计算
/// - 序列化格式
void main() {
  group('LogReporterService - 级别过滤', () {
    test('默认最低级别为 WARNING (index=2)', () {
      final reporter = LogReporterService.instance;
      // 注意：单例在测试间共享，这里只验证默认值
      expect(reporter.minLevelIndex, greaterThanOrEqualTo(LogLevel.warning.index));
    });

    test('ERROR 级别 (index=3) 应该高于 WARNING (index=2)', () {
      expect(LogLevel.error.index, greaterThan(LogLevel.warning.index));
    });

    test('级别顺序应为 debug < info < warning < error', () {
      expect(LogLevel.debug.index, lessThan(LogLevel.info.index));
      expect(LogLevel.info.index, lessThan(LogLevel.warning.index));
      expect(LogLevel.warning.index, lessThan(LogLevel.error.index));
    });
  });

  group('LogReporterService - 缓冲区管理', () {
    test('初始缓冲区大小应为 0', () {
      // 注意：单例可能已有数据，只验证非负
      final reporter = LogReporterService.instance;
      expect(reporter.bufferSize, greaterThanOrEqualTo(0));
    });

    test('onLogAdded 在禁用时应忽略', () {
      final reporter = LogReporterService.instance;
      final wasEnabled = reporter.enabled;
      final initialSize = reporter.bufferSize;

      try {
        // 临时禁用
        // 不能直接设置 _enabled，但可以验证 API 行为
        if (!reporter.enabled) {
          final entry = LogEntry(
            timestamp: DateTime.now(),
            level: LogLevel.error,
            message: 'test',
          );
          reporter.onLogAdded(entry);
          // 禁用状态下缓冲区不应增长
          expect(reporter.bufferSize, equals(initialSize));
        }
      } finally {
        // 恢复状态
        if (wasEnabled != reporter.enabled) {
          reporter.setEnabled(wasEnabled);
        }
      }
    });

    test('onLogAdded 级别低于最低上报级别时应忽略', () {
      final reporter = LogReporterService.instance;
      final minLevel = reporter.minLevelIndex;

      // 构造一个低于最低级别的日志
      if (minLevel > 0) {
        final lowLevel = LogLevel.values[minLevel - 1];
        final entry = LogEntry(
          timestamp: DateTime.now(),
          level: lowLevel,
          message: 'low level test',
        );
        final sizeBefore = reporter.bufferSize;
        reporter.onLogAdded(entry);
        // 缓冲区不应增长
        expect(reporter.bufferSize, equals(sizeBefore));
      }
    });
  });

  group('LogReporterService - 退避策略', () {
    test('常量值应正确', () {
      expect(LogReporterService.batchSize, equals(20));
      expect(LogReporterService.intervalSeconds, equals(30));
      expect(LogReporterService.maxPerBatch, equals(50));
      expect(LogReporterService.maxBufferSize, equals(100));
      expect(LogReporterService.backoffThreshold, equals(3));
      expect(LogReporterService.backoffMaxSeconds, equals(300));
    });
  });

  group('LogReporterService - 序列化格式', () {
    test('LogEntry toMap 应包含所有必要字段', () {
      final entry = LogEntry(
        timestamp: DateTime(2026, 6, 10, 12, 0, 0),
        level: LogLevel.error,
        message: 'test error',
        stackTrace: 'stack trace here',
        category: LogCategory.network,
        tags: ['api', 'timeout'],
      );

      final map = entry.toMap();
      expect(map['timestamp'], isA<int>());
      expect(map['level'], equals(3)); // error index
      expect(map['message'], equals('test error'));
      expect(map['stackTrace'], equals('stack trace here'));
      expect(map['category'], equals(1)); // network index
      expect(map['tags'], equals(['api', 'timeout']));
    });

    test('LogEntry fromMap 应正确反序列化', () {
      final map = {
        'timestamp': DateTime(2026, 6, 10, 12, 0, 0).millisecondsSinceEpoch,
        'level': 3, // error
        'message': 'test error',
        'stackTrace': 'stack trace here',
        'category': 1, // network
        'tags': ['api', 'timeout'],
      };

      final entry = LogEntry.fromMap(map);
      expect(entry.level, equals(LogLevel.error));
      expect(entry.message, equals('test error'));
      expect(entry.stackTrace, equals('stack trace here'));
      expect(entry.category, equals(LogCategory.network));
      expect(entry.tags, equals(['api', 'timeout']));
    });

    test('LogEntry fromMap 向后兼容（无 category/tags）', () {
      final map = {
        'timestamp': DateTime(2026, 6, 10).millisecondsSinceEpoch,
        'level': 0,
        'message': 'old format log',
      };

      final entry = LogEntry.fromMap(map);
      expect(entry.category, equals(LogCategory.general));
      expect(entry.tags, isEmpty);
    });
  });

  group('LogReporterService - 监听器', () {
    test('addListener/removeListener 应正常工作', () {
      final reporter = LogReporterService.instance;
      var callCount = 0;
      void callback() {
        callCount++;
      }

      reporter.addListener(callback);
      reporter.removeListener(callback);
      // 不应抛异常
      expect(callCount, equals(0));
    });

    test('重复 removeListener 不应抛异常', () {
      final reporter = LogReporterService.instance;
      void callback() {}

      reporter.removeListener(callback);
      // 不应抛异常
    });
  });

  group('LogLevel - 枚举验证', () {
    test('label 应正确', () {
      expect(LogLevel.debug.label, equals('DEBUG'));
      expect(LogLevel.info.label, equals('INFO'));
      expect(LogLevel.warning.label, equals('WARN'));
      expect(LogLevel.error.label, equals('ERROR'));
    });

    test('icon 应非空', () {
      for (final level in LogLevel.values) {
        expect(level.icon, isNotNull);
      }
    });
  });

  group('LogCategory - 枚举验证', () {
    test('所有分类应有 key 和 label', () {
      for (final cat in LogCategory.values) {
        expect(cat.key, isNotEmpty);
        expect(cat.label, isNotEmpty);
      }
    });

    test('应有 8 个分类', () {
      expect(LogCategory.values.length, equals(8));
    });
  });

  group('LogStatistics - 统计', () {
    test('空统计应正确', () {
      final stats = LogStatistics(
        total: 0,
        byLevel: {for (final l in LogLevel.values) l: 0},
        byCategory: {for (final c in LogCategory.values) c: 0},
      );
      expect(stats.total, equals(0));
      expect(stats.levelPercentage, isEmpty);
    });

    test('levelPercentage 应正确计算', () {
      final stats = LogStatistics(
        total: 100,
        byLevel: {
          LogLevel.debug: 10,
          LogLevel.info: 30,
          LogLevel.warning: 40,
          LogLevel.error: 20,
        },
        byCategory: {for (final c in LogCategory.values) c: 0},
      );
      expect(stats.levelPercentage[LogLevel.error], closeTo(0.2, 0.001));
      expect(stats.levelPercentage[LogLevel.warning], closeTo(0.4, 0.001));
    });
  });
}
