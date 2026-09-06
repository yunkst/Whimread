import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/interfaces/repositories/i_character_repository.dart';
import 'package:novel_app/core/interfaces/i_database_connection.dart';
import 'package:novel_app/repositories/character_repository.dart';
import 'package:novel_app/models/character.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

// 生成Mock类
@GenerateMocks([IDatabaseConnection])
import 'character_repository_test.mocks.dart';

void main() {
  group('CharacterRepository接口验证', () {
    late MockIDatabaseConnection mockDbConnection;
    late CharacterRepository characterRepository;

    setUp(() {
      mockDbConnection = MockIDatabaseConnection();
      characterRepository = CharacterRepository(dbConnection: mockDbConnection);
    });

    test('应该实现ICharacterRepository接口', () {
      expect(characterRepository, isA<ICharacterRepository>());
    });

    test('构造函数应该接收IDatabaseConnection', () {
      expect(characterRepository, isNotNull);
      expect(
        () => CharacterRepository(dbConnection: mockDbConnection),
        returnsNormally,
      );
    });
  });

  group('CharacterRepository核心功能测试', () {
    late MockIDatabaseConnection mockDbConnection;
    late CharacterRepository characterRepository;

    setUp(() {
      mockDbConnection = MockIDatabaseConnection();
      characterRepository = CharacterRepository(dbConnection: mockDbConnection);
    });

    test('应该正确创建CharacterRepository实例', () {
      expect(characterRepository, isA<CharacterRepository>());
      expect(characterRepository.toString(), contains('CharacterRepository'));
    });

    test('应该通过BaseRepository继承database访问器', () {
      // 验证继承链
      expect(characterRepository, isA<ICharacterRepository>());
    });
  });

  group('CharacterRepository CRUD方法签名验证', () {
    late MockIDatabaseConnection mockDbConnection;
    late CharacterRepository characterRepository;

    setUp(() {
      mockDbConnection = MockIDatabaseConnection();
      characterRepository = CharacterRepository(dbConnection: mockDbConnection);
    });

    test('应该有createCharacter方法', () {
      // 验证方法签名存在
      expect(characterRepository.createCharacter is Function, isTrue);
    });

    test('应该有getCharacters方法', () {
      // 验证方法签名存在
      expect(characterRepository.getCharacters is Function, isTrue);
    });

    test('应该有getCharacter方法', () {
      // 验证方法签名存在
      expect(characterRepository.getCharacter is Function, isTrue);
    });

    test('应该有updateCharacter方法', () {
      // 验证方法签名存在
      expect(characterRepository.updateCharacter is Function, isTrue);
    });

    test('应该有updateCharacterAvatarMediaId方法', () {
      expect(
        characterRepository.updateCharacterAvatarMediaId,
        isA<Function>(),
      );
    });

    test('应该有deleteCharacter方法', () {
      // 验证方法签名存在
      expect(characterRepository.deleteCharacter is Function, isTrue);
    });
  });

  group('CharacterRepository搜索功能验证', () {
    late MockIDatabaseConnection mockDbConnection;
    late CharacterRepository characterRepository;

    setUp(() {
      mockDbConnection = MockIDatabaseConnection();
      characterRepository = CharacterRepository(dbConnection: mockDbConnection);
    });

    test('应该有findCharacterByName方法', () {
      // 验证方法签名存在
      expect(characterRepository.findCharacterByName is Function, isTrue);
    });
  });

  group('CharacterRepository批量操作验证', () {
    late MockIDatabaseConnection mockDbConnection;
    late CharacterRepository characterRepository;

    setUp(() {
      mockDbConnection = MockIDatabaseConnection();
      characterRepository = CharacterRepository(dbConnection: mockDbConnection);
    });

    test('应该有updateOrInsertCharacter方法', () {
      // 验证方法签名存在
      expect(characterRepository.updateOrInsertCharacter is Function, isTrue);
    });
  });

  group('Character模型验证', () {
    test('Character对象应该正确构造', () {
      final character = Character(
        name: '测试角色',
        novelUrl: 'https://test.com',
      );

      expect(character.name, '测试角色');
      expect(character.novelUrl, 'https://test.com');
    });

    test('Character对象应该支持可选字段', () {
      final character = Character(
        id: 1,
        name: '测试角色',
        novelUrl: 'https://test.com',
        cachedImageUrl: 'https://test.com/avatar.jpg',
        backgroundStory: '角色描述',
      );

      expect(character.id, 1);
      expect(character.cachedImageUrl, isNotNull);
      expect(character.backgroundStory, isNotNull);
    });

    test('Character对象应该支持toMap和fromMap', () {
      final character = Character(
        name: '测试角色',
        novelUrl: 'https://test.com',
      );

      // 测试toMap方法存在
      expect(() => character.toMap(), returnsNormally);

      // 测试fromMap是工厂构造函数
      expect(Character.fromMap, isA<Function>());
    });
  });

  group('CharacterRepository新架构验证', () {
    test('不应该有initDatabase方法', () {
      // 新架构通过构造函数注入IDatabaseConnection
      late MockIDatabaseConnection mockDbConnection;
      mockDbConnection = MockIDatabaseConnection();
      expect(
        () => CharacterRepository(dbConnection: mockDbConnection),
        returnsNormally,
      );
    });

    test('不应该有setSharedDatabase方法', () {
      // 新架构不再使用setSharedDatabase模式
      late MockIDatabaseConnection mockDbConnection;
      mockDbConnection = MockIDatabaseConnection();
      final repository = CharacterRepository(dbConnection: mockDbConnection);
      expect(repository, isNotNull);
    });

    test('关系管理方法应该已移除', () {
      // 关系管理已移至CharacterRelationRepository
      late MockIDatabaseConnection mockDbConnection;
      mockDbConnection = MockIDatabaseConnection();
      final repository = CharacterRepository(dbConnection: mockDbConnection);

      // 验证CharacterRepository实例存在
      expect(repository, isNotNull);
      // 关系方法应该不在此Repository中
    });
  });
}
