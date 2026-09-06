//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'video_status_response.g.dart';

/// 视频状态查询响应模式.
///
/// Properties:
/// * [imgName] - 图片名称
/// * [hasVideo] - 是否存在视频
/// * [videoStatus] 
/// * [videoFilename] 
@BuiltValue()
abstract class VideoStatusResponse implements Built<VideoStatusResponse, VideoStatusResponseBuilder> {
  /// 图片名称
  @BuiltValueField(wireName: r'img_name')
  String get imgName;

  /// 是否存在视频
  @BuiltValueField(wireName: r'has_video')
  bool get hasVideo;

  @BuiltValueField(wireName: r'video_status')
  String? get videoStatus;

  @BuiltValueField(wireName: r'video_filename')
  String? get videoFilename;

  VideoStatusResponse._();

  factory VideoStatusResponse([void updates(VideoStatusResponseBuilder b)]) = _$VideoStatusResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VideoStatusResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VideoStatusResponse> get serializer => _$VideoStatusResponseSerializer();
}

class _$VideoStatusResponseSerializer implements PrimitiveSerializer<VideoStatusResponse> {
  @override
  final Iterable<Type> types = const [VideoStatusResponse, _$VideoStatusResponse];

  @override
  final String wireName = r'VideoStatusResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VideoStatusResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'img_name';
    yield serializers.serialize(
      object.imgName,
      specifiedType: const FullType(String),
    );
    yield r'has_video';
    yield serializers.serialize(
      object.hasVideo,
      specifiedType: const FullType(bool),
    );
    if (object.videoStatus != null) {
      yield r'video_status';
      yield serializers.serialize(
        object.videoStatus,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.videoFilename != null) {
      yield r'video_filename';
      yield serializers.serialize(
        object.videoFilename,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    VideoStatusResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required VideoStatusResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'img_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.imgName = valueDes;
          break;
        case r'has_video':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasVideo = valueDes;
          break;
        case r'video_status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.videoStatus = valueDes;
          break;
        case r'video_filename':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.videoFilename = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  VideoStatusResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VideoStatusResponseBuilder();
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

