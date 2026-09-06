//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scene_image_delete_request.g.dart';

/// 删除场面图片请求模式.
///
/// Properties:
/// * [taskId] - 场面绘制任务ID
/// * [filename] - 要删除的图片文件名
@BuiltValue()
abstract class SceneImageDeleteRequest implements Built<SceneImageDeleteRequest, SceneImageDeleteRequestBuilder> {
  /// 场面绘制任务ID
  @BuiltValueField(wireName: r'task_id')
  String get taskId;

  /// 要删除的图片文件名
  @BuiltValueField(wireName: r'filename')
  String get filename;

  SceneImageDeleteRequest._();

  factory SceneImageDeleteRequest([void updates(SceneImageDeleteRequestBuilder b)]) = _$SceneImageDeleteRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SceneImageDeleteRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SceneImageDeleteRequest> get serializer => _$SceneImageDeleteRequestSerializer();
}

class _$SceneImageDeleteRequestSerializer implements PrimitiveSerializer<SceneImageDeleteRequest> {
  @override
  final Iterable<Type> types = const [SceneImageDeleteRequest, _$SceneImageDeleteRequest];

  @override
  final String wireName = r'SceneImageDeleteRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SceneImageDeleteRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'task_id';
    yield serializers.serialize(
      object.taskId,
      specifiedType: const FullType(String),
    );
    yield r'filename';
    yield serializers.serialize(
      object.filename,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SceneImageDeleteRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SceneImageDeleteRequestBuilder result,
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
        case r'filename':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.filename = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SceneImageDeleteRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SceneImageDeleteRequestBuilder();
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

