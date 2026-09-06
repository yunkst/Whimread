//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'role_regenerate_request.g.dart';

/// 重新生成相似图片请求模式.
///
/// Properties:
/// * [imgUrl] - 参考图片URL
/// * [count] - 生成图片数量
/// * [model] 
@BuiltValue()
abstract class RoleRegenerateRequest implements Built<RoleRegenerateRequest, RoleRegenerateRequestBuilder> {
  /// 参考图片URL
  @BuiltValueField(wireName: r'img_url')
  String get imgUrl;

  /// 生成图片数量
  @BuiltValueField(wireName: r'count')
  int get count;

  @BuiltValueField(wireName: r'model')
  String? get model;

  RoleRegenerateRequest._();

  factory RoleRegenerateRequest([void updates(RoleRegenerateRequestBuilder b)]) = _$RoleRegenerateRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RoleRegenerateRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RoleRegenerateRequest> get serializer => _$RoleRegenerateRequestSerializer();
}

class _$RoleRegenerateRequestSerializer implements PrimitiveSerializer<RoleRegenerateRequest> {
  @override
  final Iterable<Type> types = const [RoleRegenerateRequest, _$RoleRegenerateRequest];

  @override
  final String wireName = r'RoleRegenerateRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RoleRegenerateRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'img_url';
    yield serializers.serialize(
      object.imgUrl,
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
    RoleRegenerateRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RoleRegenerateRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'img_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.imgUrl = valueDes;
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
  RoleRegenerateRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RoleRegenerateRequestBuilder();
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

