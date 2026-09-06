//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'image_to_video_response.g.dart';

/// 图生视频生成响应模式.
///
/// Properties:
/// * [taskId] - 视频生成任务ID
/// * [imgName] - 图片名称
/// * [status] - 任务状态: pending/running/completed/failed
/// * [message] - 处理消息
@BuiltValue()
abstract class ImageToVideoResponse implements Built<ImageToVideoResponse, ImageToVideoResponseBuilder> {
  /// 视频生成任务ID
  @BuiltValueField(wireName: r'task_id')
  int get taskId;

  /// 图片名称
  @BuiltValueField(wireName: r'img_name')
  String get imgName;

  /// 任务状态: pending/running/completed/failed
  @BuiltValueField(wireName: r'status')
  String get status;

  /// 处理消息
  @BuiltValueField(wireName: r'message')
  String get message;

  ImageToVideoResponse._();

  factory ImageToVideoResponse([void updates(ImageToVideoResponseBuilder b)]) = _$ImageToVideoResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ImageToVideoResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ImageToVideoResponse> get serializer => _$ImageToVideoResponseSerializer();
}

class _$ImageToVideoResponseSerializer implements PrimitiveSerializer<ImageToVideoResponse> {
  @override
  final Iterable<Type> types = const [ImageToVideoResponse, _$ImageToVideoResponse];

  @override
  final String wireName = r'ImageToVideoResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ImageToVideoResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'task_id';
    yield serializers.serialize(
      object.taskId,
      specifiedType: const FullType(int),
    );
    yield r'img_name';
    yield serializers.serialize(
      object.imgName,
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
    ImageToVideoResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ImageToVideoResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'task_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.taskId = valueDes;
          break;
        case r'img_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.imgName = valueDes;
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
  ImageToVideoResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ImageToVideoResponseBuilder();
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

