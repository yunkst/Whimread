//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'source_site.g.dart';

/// Source site information schema.
///
/// Properties:
/// * [id] 
/// * [name] 
/// * [baseUrl] 
/// * [description] 
/// * [enabled] 
/// * [searchEnabled] 
/// * [searchReason] 
/// * [searchHint] 
@BuiltValue()
abstract class SourceSite implements Built<SourceSite, SourceSiteBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'base_url')
  String get baseUrl;

  @BuiltValueField(wireName: r'description')
  String get description;

  @BuiltValueField(wireName: r'enabled')
  bool get enabled;

  @BuiltValueField(wireName: r'search_enabled')
  bool get searchEnabled;

  @BuiltValueField(wireName: r'search_reason')
  String? get searchReason;

  @BuiltValueField(wireName: r'search_hint')
  String? get searchHint;

  SourceSite._();

  factory SourceSite([void updates(SourceSiteBuilder b)]) = _$SourceSite;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SourceSiteBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SourceSite> get serializer => _$SourceSiteSerializer();
}

class _$SourceSiteSerializer implements PrimitiveSerializer<SourceSite> {
  @override
  final Iterable<Type> types = const [SourceSite, _$SourceSite];

  @override
  final String wireName = r'SourceSite';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SourceSite object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'base_url';
    yield serializers.serialize(
      object.baseUrl,
      specifiedType: const FullType(String),
    );
    yield r'description';
    yield serializers.serialize(
      object.description,
      specifiedType: const FullType(String),
    );
    yield r'enabled';
    yield serializers.serialize(
      object.enabled,
      specifiedType: const FullType(bool),
    );
    yield r'search_enabled';
    yield serializers.serialize(
      object.searchEnabled,
      specifiedType: const FullType(bool),
    );
    if (object.searchReason != null) {
      yield r'search_reason';
      yield serializers.serialize(
        object.searchReason,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.searchHint != null) {
      yield r'search_hint';
      yield serializers.serialize(
        object.searchHint,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SourceSite object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SourceSiteBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'base_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.baseUrl = valueDes;
          break;
        case r'description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.description = valueDes;
          break;
        case r'enabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.enabled = valueDes;
          break;
        case r'search_enabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.searchEnabled = valueDes;
          break;
        case r'search_reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.searchReason = valueDes;
          break;
        case r'search_hint':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.searchHint = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SourceSite deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SourceSiteBuilder();
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

