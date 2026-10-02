/// v53 迁移测试：角色卡共享 + 版本管理
///
/// 验证：
/// - 升级路径 v52 → v53：characters 加 speechStyle/currentState 列，
///   character_revisions 表和索引被创建
/// - 升级后角色卡可写入新列、版本行可插入并按角色查询
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_migrations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> openAtVersion(int version) => openDatabase(
        inMemoryDatabasePath,
        version: version,
        singleInstance: false,
        onCreate: (db, v) async {
          await DatabaseMigrations.createV1Tables(db);
          await DatabaseMigrations.upgrade(db, 1, v);
        },
      );

  test('升级路径 v52 → v53：新列与 character_revisions 表/索引创建', () async {
    final db = await openAtVersion(52);

    final tablesBefore = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='character_revisions'");
    expect(tablesBefore, isEmpty, reason: 'v52 不应存在 character_revisions 表');

    await DatabaseMigrations.upgrade(db, 52, DatabaseMigrations.currentVersion);

    final tablesAfter = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name='character_revisions'");
    expect(tablesAfter, hasLength(1));

    final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND name='idx_character_revisions_char'");
    expect(indexes, hasLength(1));

    final columns = await db.rawQuery('PRAGMA table_info(characters)');
    final names = columns.map((c) => c['name']).toSet();
    expect(names, containsAll(['speechStyle', 'currentState']));
    await db.close();
  });

  test('升级后：角色卡新列可写入，版本行可插入并按角色查询', () async {
    final db = await openAtVersion(52);
    await DatabaseMigrations.upgrade(db, 52, DatabaseMigrations.currentVersion);

    // 角色卡（沿用既有列 + 新列）
    final charId = await db.insert('characters', {
      'novelUrl': 'u1',
      'name': '林昭',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'speechStyle': '冷淡寡言',
      'currentState': '重伤初愈',
    });
    final card =
        await db.query('characters', where: 'id = ?', whereArgs: [charId]);
    expect(card.first['speechStyle'], '冷淡寡言');
    expect(card.first['currentState'], '重伤初愈');

    // 版本记录（快照 + 来源 + 原因）
    final revId = await db.insert('character_revisions', {
      'characterId': charId,
      'snapshotJson': '{"id":$charId,"novelUrl":"u1","name":"林昭"}',
      'source': 'text_game',
      'sourceRef': '文字游戏《试炼》',
      'reason': '击败风笑天，获得玄重尺',
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    final revisions = await db.query('character_revisions',
        where: 'characterId = ?', whereArgs: [charId]);
    expect(revisions, hasLength(1));
    expect(revisions.first['id'], revId);
    expect(revisions.first['source'], 'text_game');
    await db.close();
  });
}
