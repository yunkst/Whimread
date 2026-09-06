//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'role_info.g.dart';

/// 统一角色信息模型 - 增强版，支持自动序列化.
///
/// Properties:
/// * [id] - Flutter自增ID
/// * [name] - 角色姓名
/// * [gender] 
/// * [age] 
/// * [occupation] 
/// * [personality] 
/// * [appearanceFeatures] 
/// * [bodyType] 
/// * [clothingStyle] 
/// * [backgroundStory] 
/// * [facePrompts] 
/// * [bodyPrompts] 
@BuiltValue()
abstract class RoleInfo implements Built<RoleInfo, RoleInfoBuilder> {
  /// Flutter自增ID
  @BuiltValueField(wireName: r'id')
  int get id;

  /// 角色姓名
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'gender')
  String? get gender;

  @BuiltValueField(wireName: r'age')
  int? get age;

  @BuiltValueField(wireName: r'occupation')
  String? get occupation;

  @BuiltValueField(wireName: r'personality')
  String? get personality;

  @BuiltValueField(wireName: r'appearance_features')
  String? get appearanceFeatures;

  @BuiltValueField(wireName: r'body_type')
  String? get bodyType;

  @BuiltValueField(wireName: r'clothing_style')
  String? get clothingStyle;

  @BuiltValueField(wireName: r'background_story')
  String? get backgroundStory;

  @BuiltValueField(wireName: r'face_prompts')
  String? get facePrompts;

  @BuiltValueField(wireName: r'body_prompts')
  String? get bodyPrompts;

  RoleInfo._();

  factory RoleInfo([void updates(RoleInfoBuilder b)]) = _$RoleInfo;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RoleInfoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RoleInfo> get serializer => _$RoleInfoSerializer();
}

class _$RoleInfoSerializer implements PrimitiveSerializer<RoleInfo> {
  @override
  final Iterable<Type> types = const [RoleInfo, _$RoleInfo];

  @override
  final String wireName = r'RoleInfo';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RoleInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(int),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.gender != null) {
      yield r'gender';
      yield serializers.serialize(
        object.gender,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.age != null) {
      yield r'age';
      yield serializers.serialize(
        object.age,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.occupation != null) {
      yield r'occupation';
      yield serializers.serialize(
        object.occupation,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.personality != null) {
      yield r'personality';
      yield serializers.serialize(
        object.personality,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.appearanceFeatures != null) {
      yield r'appearance_features';
      yield serializers.serialize(
        object.appearanceFeatures,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.bodyType != null) {
      yield r'body_type';
      yield serializers.serialize(
        object.bodyType,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.clothingStyle != null) {
      yield r'clothing_style';
      yield serializers.serialize(
        object.clothingStyle,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.backgroundStory != null) {
      yield r'background_story';
      yield serializers.serialize(
        object.backgroundStory,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.facePrompts != null) {
      yield r'face_prompts';
      yield serializers.serialize(
        object.facePrompts,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.bodyPrompts != null) {
      yield r'body_prompts';
      yield serializers.serialize(
        object.bodyPrompts,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RoleInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RoleInfoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.id = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'gender':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.gender = valueDes;
          break;
        case r'age':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.age = valueDes;
          break;
        case r'occupation':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.occupation = valueDes;
          break;
        case r'personality':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.personality = valueDes;
          break;
        case r'appearance_features':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.appearanceFeatures = valueDes;
          break;
        case r'body_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.bodyType = valueDes;
          break;
        case r'clothing_style':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.clothingStyle = valueDes;
          break;
        case r'background_story':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.backgroundStory = valueDes;
          break;
        case r'face_prompts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.facePrompts = valueDes;
          break;
        case r'body_prompts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.bodyPrompts = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RoleInfo deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RoleInfoBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

