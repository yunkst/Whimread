//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:novel_api/src/model/workflow_info.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'models_response.g.dart';

/// 模型列表响应模式.
///
/// Properties:
/// * [text2img] - 文生图模型列表
/// * [img2video] - 图生视频模型列表
@BuiltValue()
abstract class ModelsResponse implements Built<ModelsResponse, ModelsResponseBuilder> {
  /// 文生图模型列表
  @BuiltValueField(wireName: r'text2img')
  BuiltList<WorkflowInfo>? get text2img;

  /// 图生视频模型列表
  @BuiltValueField(wireName: r'img2video')
  BuiltList<WorkflowInfo>? get img2video;

  ModelsResponse._();

  factory ModelsResponse([void updates(ModelsResponseBuilder b)]) = _$ModelsResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModelsResponseBuilder b) => b
      ..text2img = ListBuilder()
      ..img2video = ListBuilder();

  @BuiltValueSerializer(custom: true)
  static Serializer<ModelsResponse> get serializer => _$ModelsResponseSerializer();
}

class _$ModelsResponseSerializer implements PrimitiveSerializer<ModelsResponse> {
  @override
  final Iterable<Type> types = const [ModelsResponse, _$ModelsResponse];

  @override
  final String wireName = r'ModelsResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModelsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.text2img != null) {
      yield r'text2img';
      yield serializers.serialize(
        object.text2img,
        specifiedType: const FullType(BuiltList, [FullType(WorkflowInfo)]),
      );
    }
    if (object.img2video != null) {
      yield r'img2video';
      yield serializers.serialize(
        object.img2video,
        specifiedType: const FullType(BuiltList, [FullType(WorkflowInfo)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ModelsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModelsResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'text2img':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(WorkflowInfo)]),
          ) as BuiltList<WorkflowInfo>;
          result.text2img.replace(valueDes);
          break;
        case r'img2video':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(WorkflowInfo)]),
          ) as BuiltList<WorkflowInfo>;
          result.img2video.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModelsResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModelsResponseBuilder();
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

