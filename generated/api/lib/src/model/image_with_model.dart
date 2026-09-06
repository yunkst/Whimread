//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'image_with_model.g.dart';

/// 带模型信息的图片
///
/// Properties:
/// * [url] - 图片URL
/// * [modelName] 
@BuiltValue()
abstract class ImageWithModel implements Built<ImageWithModel, ImageWithModelBuilder> {
  /// 图片URL
  @BuiltValueField(wireName: r'url')
  String get url;

  @BuiltValueField(wireName: r'model_name')
  String? get modelName;

  ImageWithModel._();

  factory ImageWithModel([void updates(ImageWithModelBuilder b)]) = _$ImageWithModel;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ImageWithModelBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ImageWithModel> get serializer => _$ImageWithModelSerializer();
}

class _$ImageWithModelSerializer implements PrimitiveSerializer<ImageWithModel> {
  @override
  final Iterable<Type> types = const [ImageWithModel, _$ImageWithModel];

  @override
  final String wireName = r'ImageWithModel';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ImageWithModel object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'url';
    yield serializers.serialize(
      object.url,
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
    ImageWithModel object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ImageWithModelBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
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
  ImageWithModel deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ImageWithModelBuilder();
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

