//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'novel.g.dart';

/// Novel metadata schema.
///
/// Properties:
/// * [title] 
/// * [author] 
/// * [url] 
@BuiltValue()
abstract class Novel implements Built<Novel, NovelBuilder> {
  @BuiltValueField(wireName: r'title')
  String get title;

  @BuiltValueField(wireName: r'author')
  String get author;

  @BuiltValueField(wireName: r'url')
  String get url;

  Novel._();

  factory Novel([void updates(NovelBuilder b)]) = _$Novel;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NovelBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Novel> get serializer => _$NovelSerializer();
}

class _$NovelSerializer implements PrimitiveSerializer<Novel> {
  @override
  final Iterable<Type> types = const [Novel, _$Novel];

  @override
  final String wireName = r'Novel';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Novel object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    yield r'author';
    yield serializers.serialize(
      object.author,
      specifiedType: const FullType(String),
    );
    yield r'url';
    yield serializers.serialize(
      object.url,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Novel object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NovelBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.title = valueDes;
          break;
        case r'author':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.author = valueDes;
          break;
        case r'url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.url = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Novel deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NovelBuilder();
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

