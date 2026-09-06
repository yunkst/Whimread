//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scene_regenerate_request.g.dart';

/// 场面绘制重新生成请求模式.
///
/// Properties:
/// * [taskId] - 原始任务ID
/// * [count] - 生成图片数量
/// * [model] 
@BuiltValue()
abstract class SceneRegenerateRequest implements Built<SceneRegenerateRequest, SceneRegenerateRequestBuilder> {
  /// 原始任务ID
  @BuiltValueField(wireName: r'task_id')
  String get taskId;

  /// 生成图片数量
  @BuiltValueField(wireName: r'count')
  int get count;

  @BuiltValueField(wireName: r'model')
  String? get model;

  SceneRegenerateRequest._();

  factory SceneRegenerateRequest([void updates(SceneRegenerateRequestBuilder b)]) = _$SceneRegenerateRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SceneRegenerateRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SceneRegenerateRequest> get serializer => _$SceneRegenerateRequestSerializer();
}

class _$SceneRegenerateRequestSerializer implements PrimitiveSerializer<SceneRegenerateRequest> {
  @override
  final Iterable<Type> types = const [SceneRegenerateRequest, _$SceneRegenerateRequest];

  @override
  final String wireName = r'SceneRegenerateRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SceneRegenerateRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'task_id';
    yield serializers.serialize(
      object.taskId,
      specifiedType: const FullType(String),
    );
    yield r'count';
    yield serializers.serialize(
      object.count,
      specifiedType: const FullType(int),
    );
    if (object.model != null) {
      yield r'model';
      yield serializers.serialize(
        object.model,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SceneRegenerateRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SceneRegenerateRequestBuilder result,
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
        case r'count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.count = valueDes;
          break;
        case r'model':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.model = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SceneRegenerateRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SceneRegenerateRequestBuilder();
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

