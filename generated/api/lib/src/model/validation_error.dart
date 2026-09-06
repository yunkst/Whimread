//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:novel_api/src/model/validation_error_loc_inner.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'validation_error.g.dart';

/// ValidationError
///
/// Properties:
/// * [loc] 
/// * [msg] 
/// * [type] 
/// * [input] 
/// * [ctx] 
@BuiltValue()
abstract class ValidationError implements Built<ValidationError, ValidationErrorBuilder> {
  @BuiltValueField(wireName: r'loc')
  BuiltList<ValidationErrorLocInner> get loc;

  @BuiltValueField(wireName: r'msg')
  String get msg;

  @BuiltValueField(wireName: r'type')
  String get type;

  @BuiltValueField(wireName: r'input')
  JsonObject? get input;

  @BuiltValueField(wireName: r'ctx')
  JsonObject? get ctx;

  ValidationError._();

  factory ValidationError([void updates(ValidationErrorBuilder b)]) = _$ValidationError;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ValidationErrorBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ValidationError> get serializer => _$ValidationErrorSerializer();
}

class _$ValidationErrorSerializer implements PrimitiveSerializer<ValidationError> {
  @override
  final Iterable<Type> types = const [ValidationError, _$ValidationError];

  @override
  final String wireName = r'ValidationError';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ValidationError object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'loc';
    yield serializers.serialize(
      object.loc,
      specifiedType: const FullType(BuiltList, [FullType(ValidationErrorLocInner)]),
    );
    yield r'msg';
    yield serializers.serialize(
      object.msg,
      specifiedType: const FullType(String),
    );
    yield r'type';
    yield serializers.serialize(
      object.type,
      specifiedType: const FullType(String),
    );
    if (object.input != null) {
      yield r'input';
      yield serializers.serialize(
        object.input,
        specifiedType: const FullType.nullable(JsonObject),
      );
    }
    if (object.ctx != null) {
      yield r'ctx';
      yield serializers.serialize(
        object.ctx,
        specifiedType: const FullType(JsonObject),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ValidationError object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ValidationErrorBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'loc':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ValidationErrorLocInner)]),
          ) as BuiltList<ValidationErrorLocInner>;
          result.loc.replace(valueDes);
          break;
        case r'msg':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.msg = valueDes;
          break;
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.type = valueDes;
          break;
        case r'input':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(JsonObject),
          ) as JsonObject?;
          if (valueDes == null) continue;
          result.input = valueDes;
          break;
        case r'ctx':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(JsonObject),
          ) as JsonObject;
          result.ctx = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ValidationError deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ValidationErrorBuilder();
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

