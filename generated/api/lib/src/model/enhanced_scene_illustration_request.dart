//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:novel_api/src/model/role_info.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'enhanced_scene_illustration_request.g.dart';

/// 增强的场景插图请求模型 - 支持多种输入格式和自动序列化.
///
/// Properties:
/// * [chaptersContent] - 章节内容
/// * [taskId] - 任务标识符
/// * [roles] - 角色信息列表
/// * [num_] - 生成图片数量
/// * [modelName] 
@BuiltValue()
abstract class EnhancedSceneIllustrationRequest implements Built<EnhancedSceneIllustrationRequest, EnhancedSceneIllustrationRequestBuilder> {
  /// 章节内容
  @BuiltValueField(wireName: r'chapters_content')
  String get chaptersContent;

  /// 任务标识符
  @BuiltValueField(wireName: r'task_id')
  String get taskId;

  /// 角色信息列表
  @BuiltValueField(wireName: r'roles')
  BuiltList<RoleInfo> get roles;

  /// 生成图片数量
  @BuiltValueField(wireName: r'num')
  int get num_;

  @BuiltValueField(wireName: r'model_name')
  String? get modelName;

  EnhancedSceneIllustrationRequest._();

  factory EnhancedSceneIllustrationRequest([void updates(EnhancedSceneIllustrationRequestBuilder b)]) = _$EnhancedSceneIllustrationRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EnhancedSceneIllustrationRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EnhancedSceneIllustrationRequest> get serializer => _$EnhancedSceneIllustrationRequestSerializer();
}

class _$EnhancedSceneIllustrationRequestSerializer implements PrimitiveSerializer<EnhancedSceneIllustrationRequest> {
  @override
  final Iterable<Type> types = const [EnhancedSceneIllustrationRequest, _$EnhancedSceneIllustrationRequest];

  @override
  final String wireName = r'EnhancedSceneIllustrationRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EnhancedSceneIllustrationRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'chapters_content';
    yield serializers.serialize(
      object.chaptersContent,
      specifiedType: const FullType(String),
    );
    yield r'task_id';
    yield serializers.serialize(
      object.taskId,
      specifiedType: const FullType(String),
    );
    yield r'roles';
    yield serializers.serialize(
      object.roles,
      specifiedType: const FullType(BuiltList, [FullType(RoleInfo)]),
    );
    yield r'num';
    yield serializers.serialize(
      object.num_,
      specifiedType: const FullType(int),
    );
    if (object.modelName != null) {
      yield r'model_name';
      yield serializers.serialize(
        object.modelName,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    EnhancedSceneIllustrationRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required EnhancedSceneIllustrationRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'chapters_content':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.chaptersContent = valueDes;
          break;
        case r'task_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.taskId = valueDes;
          break;
        case r'roles':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RoleInfo)]),
          ) as BuiltList<RoleInfo>;
          result.roles.replace(valueDes);
          break;
        case r'num':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.num_ = valueDes;
          break;
        case r'model_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.modelName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EnhancedSceneIllustrationRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EnhancedSceneIllustrationRequestBuilder();
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

