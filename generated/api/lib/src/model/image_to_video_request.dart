//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'image_to_video_request.g.dart';

/// 图生视频请求模式.
///
/// Properties:
/// * [imgName] - 图片名称
/// * [userInput] - 用户要求
/// * [modelName] 
@BuiltValue()
abstract class ImageToVideoRequest implements Built<ImageToVideoRequest, ImageToVideoRequestBuilder> {
  /// 图片名称
  @BuiltValueField(wireName: r'img_name')
  String get imgName;

  /// 用户要求
  @BuiltValueField(wireName: r'user_input')
  String get userInput;

  @BuiltValueField(wireName: r'model_name')
  String? get modelName;

  ImageToVideoRequest._();

  factory ImageToVideoRequest([void updates(ImageToVideoRequestBuilder b)]) = _$ImageToVideoRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ImageToVideoRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ImageToVideoRequest> get serializer => _$ImageToVideoRequestSerializer();
}

class _$ImageToVideoRequestSerializer implements PrimitiveSerializer<ImageToVideoRequest> {
  @override
  final Iterable<Type> types = const [ImageToVideoRequest, _$ImageToVideoRequest];

  @override
  final String wireName = r'ImageToVideoRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ImageToVideoRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'img_name';
    yield serializers.serialize(
      object.imgName,
      specifiedType: const FullType(String),
    );
    yield r'user_input';
    yield serializers.serialize(
      object.userInput,
      specifiedType: const FullType(String),
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
    ImageToVideoRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ImageToVideoRequestBuilder result,
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
        case r'user_input':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userInput = valueDes;
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
  ImageToVideoRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ImageToVideoRequestBuilder();
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

