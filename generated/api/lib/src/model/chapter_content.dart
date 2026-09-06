//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'chapter_content.g.dart';

/// Chapter content schema.
///
/// Properties:
/// * [title] 
/// * [content] 
/// * [fromCache] 
@BuiltValue()
abstract class ChapterContent implements Built<ChapterContent, ChapterContentBuilder> {
  @BuiltValueField(wireName: r'title')
  String get title;

  @BuiltValueField(wireName: r'content')
  String get content;

  @BuiltValueField(wireName: r'from_cache')
  bool? get fromCache;

  ChapterContent._();

  factory ChapterContent([void updates(ChapterContentBuilder b)]) = _$ChapterContent;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ChapterContentBuilder b) => b
      ..fromCache = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<ChapterContent> get serializer => _$ChapterContentSerializer();
}

class _$ChapterContentSerializer implements PrimitiveSerializer<ChapterContent> {
  @override
  final Iterable<Type> types = const [ChapterContent, _$ChapterContent];

  @override
  final String wireName = r'ChapterContent';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ChapterContent object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    yield r'content';
    yield serializers.serialize(
      object.content,
      specifiedType: const FullType(String),
    );
    if (object.fromCache != null) {
      yield r'from_cache';
      yield serializers.serialize(
        object.fromCache,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ChapterContent object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ChapterContentBuilder result,
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
        case r'content':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.content = valueDes;
          break;
        case r'from_cache':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.fromCache = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ChapterContent deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ChapterContentBuilder();
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

