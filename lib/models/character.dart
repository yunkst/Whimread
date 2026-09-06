import 'dart:convert';

class Character {
  final int? id;
  final String novelUrl;
  final String name;
  final int? age;
  final String? gender;
  final String? occupation;
  final String? personality;
  final String? bodyType;
  final String? clothingStyle;
  final String? appearanceFeatures;
  final String? backgroundStory;
  final String? facePrompts; // 面部提示词
  final String? bodyPrompts; // 身材提示词
  final String? cachedImageUrl; // 缓存的图集第一张图片路径
  final String? avatarMediaId; // 头像媒体资源ID（图像/视频），经 MediaView 渲染
  final List<String>? aliases; // 别名列表，上限10个
  final int? firstAppearanceChapter; // 登场章节(0-based index),空=视为§0登场
  final DateTime createdAt;
  final DateTime? updatedAt;

  Character({
    this.id,
    required this.novelUrl,
    required this.name,
    this.age,
    this.gender,
    this.occupation,
    this.personality,
    this.bodyType,
    this.clothingStyle,
    this.appearanceFeatures,
    this.backgroundStory,
    this.facePrompts, // 面部提示词
    this.bodyPrompts, // 身材提示词
    this.cachedImageUrl, // 缓存的图集第一张图片路径
    this.avatarMediaId, // 头像媒体资源ID
    this.aliases, // 别名列表
    this.firstAppearanceChapter, // 登场章节
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'novelUrl': novelUrl,
      'name': name,
      'age': age,
      'gender': gender,
      'occupation': occupation,
      'personality': personality,
      'bodyType': bodyType,
      'clothingStyle': clothingStyle,
      'appearanceFeatures': appearanceFeatures,
      'backgroundStory': backgroundStory,
      'facePrompts': facePrompts,
      'bodyPrompts': bodyPrompts,
      'cachedImageUrl': cachedImageUrl,
      'avatarMediaId': avatarMediaId,
      'aliases': aliases?.isEmpty ?? true ? null : jsonEncode(aliases),
      'firstAppearanceChapter': firstAppearanceChapter,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
    };
  }

  factory Character.fromMap(Map<String, dynamic> map) {
    List<String>? parseAliases(String? aliasesJson) {
      if (aliasesJson == null || aliasesJson.isEmpty) return null;
      try {
        final decoded = jsonDecode(aliasesJson) as List;
        return decoded.map((e) => e.toString()).toList();
      } catch (_) {
        return null;
      }
    }

    return Character(
      id: map['id']?.toInt(),
      novelUrl: map['novelUrl'] as String,
      name: map['name'] as String,
      age: map['age']?.toInt(),
      gender: map['gender'] as String?,
      occupation: map['occupation'] as String?,
      personality: map['personality'] as String?,
      bodyType: map['bodyType'] as String?,
      clothingStyle: map['clothingStyle'] as String?,
      appearanceFeatures: map['appearanceFeatures'] as String?,
      backgroundStory: map['backgroundStory'] as String?,
      facePrompts: map['facePrompts'] as String?,
      bodyPrompts: map['bodyPrompts'] as String?,
      cachedImageUrl: map['cachedImageUrl'] as String?,
      avatarMediaId: map['avatarMediaId'] as String?,
      aliases: parseAliases(map['aliases'] as String?),
      firstAppearanceChapter: map['firstAppearanceChapter'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'])
          : null,
    );
  }

  Character copyWith({
    int? id,
    String? novelUrl,
    String? name,
    int? age,
    String? gender,
    String? occupation,
    String? personality,
    String? bodyType,
    String? clothingStyle,
    String? appearanceFeatures,
    String? backgroundStory,
    String? facePrompts,
    String? bodyPrompts,
    String? cachedImageUrl,
    String? avatarMediaId,
    List<String>? aliases,
    int? firstAppearanceChapter,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Character(
      id: id ?? this.id,
      novelUrl: novelUrl ?? this.novelUrl,
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      occupation: occupation ?? this.occupation,
      personality: personality ?? this.personality,
      bodyType: bodyType ?? this.bodyType,
      clothingStyle: clothingStyle ?? this.clothingStyle,
      appearanceFeatures: appearanceFeatures ?? this.appearanceFeatures,
      backgroundStory: backgroundStory ?? this.backgroundStory,
      facePrompts: facePrompts ?? this.facePrompts,
      bodyPrompts: bodyPrompts ?? this.bodyPrompts,
      cachedImageUrl: cachedImageUrl ?? this.cachedImageUrl,
      avatarMediaId: avatarMediaId ?? this.avatarMediaId,
      aliases: aliases ?? this.aliases,
      firstAppearanceChapter: firstAppearanceChapter ?? this.firstAppearanceChapter,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  // AI友好的格式化文本输出
  static String formatForAI(List<Character> characters) {
    if (characters.isEmpty) return '无特定角色出场';

    String rolesInfo = '【出场人物】\n';

    for (int i = 0; i < characters.length; i++) {
      final char = characters[i];
      rolesInfo += '''
${i + 1}. ${char.name}
   基本信息：${char.gender ?? '未知'}，${char.age ?? '未知'}岁，${char.occupation ?? '未知职业'}
   性格特点：${char.personality ?? '待补充'}
   外貌特征：${char.appearanceFeatures ?? '待补充'}
   身材体型：${char.bodyType ?? '待补充'}
   穿衣风格：${char.clothingStyle ?? '待补充'}
   背景经历：${char.backgroundStory ?? '待补充'}
''';
    }

    return rolesInfo;
  }

  }
