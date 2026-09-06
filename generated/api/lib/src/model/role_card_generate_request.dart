//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:novel_api/src/model/role_info.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'role_card_generate_request.g.dart';

/// 人物卡图片生成请求模式.
///
/// Properties:
/// * [roleId] - 人物卡ID
/// * [roles] - 人物卡设定信息列表
/// * [model] 
@BuiltValue()
abstract class RoleCardGenerateRequest implements Built<RoleCardGenerateRequest, RoleCardGenerateRequestBuilder> {
  /// 人物卡ID
  @BuiltValueField(wireName: r'role_id')
  String get roleId;

  /// 人物卡设定信息列表
  @BuiltValueField(wireName: r'roles')
  BuiltList<RoleInfo> get roles;

  @BuiltValueField(wireName: r'model')
  String? get model;

  RoleCardGenerateRequest._();

  factory RoleCardGenerateRequest([void updates(RoleCardGenerateRequestBuilder b)]) = _$RoleCardGenerateRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RoleCardGenerateRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RoleCardGenerateRequest> get serializer => _$RoleCardGenerateRequestSerializer();
}

class _$RoleCardGenerateRequestSerializer implements PrimitiveSerializer<RoleCardGenerateRequest> {
  @override
  final Iterable<Type> types = const [RoleCardGenerateRequest, _$RoleCardGenerateRequest];

  @override
  final String wireName = r'RoleCardGenerateRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RoleCardGenerateRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'role_id';
    yield serializers.serialize(
      object.roleId,
      specifiedType: const FullType(String),
    );
    yield r'roles';
    yield serializers.serialize(
      object.roles,
      specifiedType: const FullType(BuiltList, [FullType(RoleInfo)]),
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
    RoleCardGenerateRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RoleCardGenerateRequestBuilder result,
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
        case r'roles':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RoleInfo)]),
          ) as BuiltList<RoleInfo>;
          result.roles.replace(valueDes);
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
  RoleCardGenerateRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RoleCardGenerateRequestBuilder();
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

