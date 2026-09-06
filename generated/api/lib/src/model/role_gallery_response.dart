//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'role_gallery_response.g.dart';

/// 角色图集响应模式.
///
/// Properties:
/// * [roleId] - 人物卡ID
/// * [images] - 图片URL列表
@BuiltValue()
abstract class RoleGalleryResponse implements Built<RoleGalleryResponse, RoleGalleryResponseBuilder> {
  /// 人物卡ID
  @BuiltValueField(wireName: r'role_id')
  String get roleId;

  /// 图片URL列表
  @BuiltValueField(wireName: r'images')
  BuiltList<String> get images;

  RoleGalleryResponse._();

  factory RoleGalleryResponse([void updates(RoleGalleryResponseBuilder b)]) = _$RoleGalleryResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RoleGalleryResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RoleGalleryResponse> get serializer => _$RoleGalleryResponseSerializer();
}

class _$RoleGalleryResponseSerializer implements PrimitiveSerializer<RoleGalleryResponse> {
  @override
  final Iterable<Type> types = const [RoleGalleryResponse, _$RoleGalleryResponse];

  @override
  final String wireName = r'RoleGalleryResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RoleGalleryResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'role_id';
    yield serializers.serialize(
      object.roleId,
      specifiedType: const FullType(String),
    );
    yield r'images';
    yield serializers.serialize(
      object.images,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RoleGalleryResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RoleGalleryResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'role_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.roleId = valueDes;
          break;
        case r'images':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.images.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RoleGalleryResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RoleGalleryResponseBuilder();
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

