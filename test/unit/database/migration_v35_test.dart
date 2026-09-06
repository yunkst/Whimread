import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import '../../helpers/in_memory_db.dart';

void main() {
  late Database db;
  setUp(() async {
    db = await setupInMemoryDb();
  });
  tearDown(() async => db.close());

  test('character_relationships 表有全部新列', () async {
    final cols = await db.rawQuery('PRAGMA table_info(character_relationships)');
    final names = cols.map((c) => c['name']).toSet();
    for (final n in [
      'relation_type',
      'strength',
      'start_chapter',
      'end_chapter',
      'description',
      'novel_url',
    ]) {
      expect(names, contains(n), reason: '缺列 $n');
    }
    // 旧字段 relationship_type / source/target 字段已替换
    expect(names, contains('source_character_id'));
    expect(names, contains('target_character_id'));
  });

  test('characters 表有 firstAppearanceChapter 列', () async {
    final cols = await db.rawQuery('PRAGMA table_info(characters)');
    expect(cols.map((c) => c['name']), contains('firstAppearanceChapter'));
  });

  test('唯一约束生效:同对人同章同类型不重复', () async {
    await db.insert('characters', {
      'novelUrl': 'n',
      'name': '甲',
      'createdAt': 0,
    });
    await db.insert('characters', {
      'novelUrl': 'n',
      'name': '乙',
      'createdAt': 0,
    });
    final rel = {
      'source_character_id': 1,
      'target_character_id': 2,
      'relation_type': 'friend',
      'strength': 3,
      'start_chapter': 0,
      'novel_url': 'n',
      'created_at': 0,
    };
    await db.insert('character_relationships', rel);
    expect(() => db.insert('character_relationships', rel),
        throwsA(isA<Object>()));
  });
}
