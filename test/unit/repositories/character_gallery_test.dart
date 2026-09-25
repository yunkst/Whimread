/// 角色图集 repository 测试（character_images，v50）
///
/// 覆盖：追加（sort 递增）/ 查询排序 / 移除 / 清空 /
/// deleteCharacter 与 deleteAllCharacters 的图集联动清理。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/database/database_connection.dart';
import 'package:novel_app/models/character.dart';
import 'package:novel_app/repositories/character_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../helpers/test_database_setup.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late CharacterRepository repo;

  setUp(() async {
    db = await TestDatabaseSetup.createInMemoryDatabase();
    repo = CharacterRepository(dbConnection: DatabaseConnection.forTesting(db));
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertCharacter(String name) => repo.createCharacter(Character(
        novelUrl: 'custom://gallery-test',
        name: name,
      ));

  test('addCharacterImage：sort 从 0 递增，返回带 id 的条目', () async {
    final characterId = await insertCharacter('林雪');

    final first = await repo.addCharacterImage(characterId, 'local_1');
    final second = await repo.addCharacterImage(characterId, 'local_2');

    expect(first.id, isNotNull);
    expect(first.sort, 0);
    expect(second.sort, 1);
    expect(second.id, isNot(first.id));
  });

  test('getCharacterImages：按 sort 升序返回', () async {
    final characterId = await insertCharacter('林雪');
    await repo.addCharacterImage(characterId, 'local_a');
    await repo.addCharacterImage(characterId, 'local_b');
    await repo.addCharacterImage(characterId, 'local_c');

    final images = await repo.getCharacterImages(characterId);

    expect(images.map((e) => e.mediaId).toList(),
        ['local_a', 'local_b', 'local_c']);
  });

  test('removeCharacterImage：仅删对应行', () async {
    final characterId = await insertCharacter('林雪');
    final first = await repo.addCharacterImage(characterId, 'local_a');
    await repo.addCharacterImage(characterId, 'local_b');

    final affected = await repo.removeCharacterImage(first.id!);

    expect(affected, 1);
    final rest = await repo.getCharacterImages(characterId);
    expect(rest.map((e) => e.mediaId), ['local_b']);
  });

  test('deleteCharacter：联动清理该角色的图集行', () async {
    final characterId = await insertCharacter('林雪');
    await repo.addCharacterImage(characterId, 'local_a');
    await repo.addCharacterImage(characterId, 'local_b');

    await repo.deleteCharacter(characterId);

    final rows = await db.query('character_images',
        where: 'characterId = ?', whereArgs: [characterId]);
    expect(rows, isEmpty);
  });

  test('deleteAllCharacters：清理该小说全部角色的图集行', () async {
    final id1 = await insertCharacter('甲');
    final id2 = await insertCharacter('乙');
    await repo.addCharacterImage(id1, 'local_a');
    await repo.addCharacterImage(id2, 'local_b');

    await repo.deleteAllCharacters('custom://gallery-test');

    final rows = await db.query('character_images');
    expect(rows, isEmpty);
  });
}
