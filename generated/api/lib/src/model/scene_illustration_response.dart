//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scene_illustration_response.g.dart';

/// 场面绘制任务创建响应模式.
///
/// Properties:
/// * [taskId] - 任务标识符
/// * [status] - 任务状态
/// * [message] - 响应消息
@BuiltValue()
abstract class SceneIllustrationResponse implements Built<SceneIllustrationResponse, SceneIllustrationResponseBuilder> {
  /// 任务标识符
  @BuiltValueField(wireName: r'task_id')
  String get taskId;

  /// 任务状态
  @BuiltValueField(wireName: r'status')
  String get status;

  /// 响应消息
  @BuiltValueField(wireName: r'message')
  String get message;

  SceneIllustrationResponse._();

  factory SceneIllustrationResponse([void updates(SceneIllustrationResponseBuilder b)]) = _$SceneIllustrationResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SceneIllustrationResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SceneIllustrationResponse> get serializer => _$SceneIllustrationResponseSerializer();
}

class _$SceneIllustrationResponseSerializer implements PrimitiveSerializer<SceneIllustrationResponse> {
  @override
  final Iterable<Type> types = const [SceneIllustrationResponse, _$SceneIllustrationResponse];

  @override
  final String wireName = r'SceneIllustrationResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SceneIllustrationResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'task_id';
    yield serializers.serialize(
      object.taskId,
      specifiedType: const FullType(String),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(String),
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
    SceneIllustrationResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SceneIllustrationResponseBuilder result,
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
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.status = valueDes;
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
  SceneIllustrationResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SceneIllustrationResponseBuilder();
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

