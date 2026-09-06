//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'role_image_delete_request.g.dart';

/// 删除角色图片请求模式.
///
/// Properties:
/// * [roleId] - 人物卡ID
/// * [imgUrl] - 要删除的图片URL
@BuiltValue()
abstract class RoleImageDeleteRequest implements Built<RoleImageDeleteRequest, RoleImageDeleteRequestBuilder> {
  /// 人物卡ID
  @BuiltValueField(wireName: r'role_id')
  String get roleId;

  /// 要删除的图片URL
  @BuiltValueField(wireName: r'img_url')
  String get imgUrl;

  RoleImageDeleteRequest._();

  factory RoleImageDeleteRequest([void updates(RoleImageDeleteRequestBuilder b)]) = _$RoleImageDeleteRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RoleImageDeleteRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RoleImageDeleteRequest> get serializer => _$RoleImageDeleteRequestSerializer();
}

class _$RoleImageDeleteRequestSerializer implements PrimitiveSerializer<RoleImageDeleteRequest> {
  @override
  final Iterable<Type> types = const [RoleImageDeleteRequest, _$RoleImageDeleteRequest];

  @override
  final String wireName = r'RoleImageDeleteRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RoleImageDeleteRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'role_id';
    yield serializers.serialize(
      object.roleId,
      specifiedType: const FullType(String),
    );
    yield r'img_url';
    yield serializers.serialize(
      object.imgUrl,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RoleImageDeleteRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RoleImageDeleteRequestBuilder result,
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
        case r'img_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.imgUrl = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RoleImageDeleteRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RoleImageDeleteRequestBuilder();
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

