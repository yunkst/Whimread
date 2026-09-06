//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:novel_api/src/model/image_with_model.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scene_gallery_response.g.dart';

/// 场面图片列表响应模式.
///
/// Properties:
/// * [taskId] - 场面绘制任务ID
/// * [images] - 图片列表（带模型信息）
/// * [modelName] 
/// * [modelWidth] 
/// * [modelHeight] 
@BuiltValue()
abstract class SceneGalleryResponse implements Built<SceneGalleryResponse, SceneGalleryResponseBuilder> {
  /// 场面绘制任务ID
  @BuiltValueField(wireName: r'task_id')
  String get taskId;

  /// 图片列表（带模型信息）
  @BuiltValueField(wireName: r'images')
  BuiltList<ImageWithModel> get images;

  @BuiltValueField(wireName: r'model_name')
  String? get modelName;

  @BuiltValueField(wireName: r'model_width')
  int? get modelWidth;

  @BuiltValueField(wireName: r'model_height')
  int? get modelHeight;

  SceneGalleryResponse._();

  factory SceneGalleryResponse([void updates(SceneGalleryResponseBuilder b)]) = _$SceneGalleryResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SceneGalleryResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SceneGalleryResponse> get serializer => _$SceneGalleryResponseSerializer();
}

class _$SceneGalleryResponseSerializer implements PrimitiveSerializer<SceneGalleryResponse> {
  @override
  final Iterable<Type> types = const [SceneGalleryResponse, _$SceneGalleryResponse];

  @override
  final String wireName = r'SceneGalleryResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SceneGalleryResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'task_id';
    yield serializers.serialize(
      object.taskId,
      specifiedType: const FullType(String),
    );
    yield r'images';
    yield serializers.serialize(
      object.images,
      specifiedType: const FullType(BuiltList, [FullType(ImageWithModel)]),
    );
    if (object.modelName != null) {
      yield r'model_name';
      yield serializers.serialize(
        object.modelName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.modelWidth != null) {
      yield r'model_width';
      yield serializers.serialize(
        object.modelWidth,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.modelHeight != null) {
      yield r'model_height';
      yield serializers.serialize(
        object.modelHeight,
        specifiedType: const FullType.nullable(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SceneGalleryResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SceneGalleryResponseBuilder result,
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
        case r'images':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ImageWithModel)]),
          ) as BuiltList<ImageWithModel>;
          result.images.replace(valueDes);
          break;
        case r'model_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.modelName = valueDes;
          break;
        case r'model_width':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.modelWidth = valueDes;
          break;
        case r'model_height':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.modelHeight = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SceneGalleryResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SceneGalleryResponseBuilder();
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

