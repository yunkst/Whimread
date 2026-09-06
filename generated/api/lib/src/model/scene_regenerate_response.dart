//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scene_regenerate_response.g.dart';

/// 场面绘制重新生成响应模式.
///
/// Properties:
/// * [taskId] - 原始任务ID
/// * [totalPrompts] - 生成的提示词数量
/// * [message] - 处理消息
@BuiltValue()
abstract class SceneRegenerateResponse implements Built<SceneRegenerateResponse, SceneRegenerateResponseBuilder> {
  /// 原始任务ID
  @BuiltValueField(wireName: r'task_id')
  String get taskId;

  /// 生成的提示词数量
  @BuiltValueField(wireName: r'total_prompts')
  int get totalPrompts;

  /// 处理消息
  @BuiltValueField(wireName: r'message')
  String get message;

  SceneRegenerateResponse._();

  factory SceneRegenerateResponse([void updates(SceneRegenerateResponseBuilder b)]) = _$SceneRegenerateResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SceneRegenerateResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SceneRegenerateResponse> get serializer => _$SceneRegenerateResponseSerializer();
}

class _$SceneRegenerateResponseSerializer implements PrimitiveSerializer<SceneRegenerateResponse> {
  @override
  final Iterable<Type> types = const [SceneRegenerateResponse, _$SceneRegenerateResponse];

  @override
  final String wireName = r'SceneRegenerateResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SceneRegenerateResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'task_id';
    yield serializers.serialize(
      object.taskId,
      specifiedType: const FullType(String),
    );
    yield r'total_prompts';
    yield serializers.serialize(
      object.totalPrompts,
      specifiedType: const FullType(int),
    );
    yield r'message';
    yield serializers.serialize(
      object.message,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SceneRegenerateResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SceneRegenerateResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'task_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.taskId = valueDes;
          break;
        case r'total_prompts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalPrompts = valueDes;
          break;
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SceneRegenerateResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SceneRegenerateResponseBuilder();
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

