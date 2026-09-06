//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:novel_api/src/model/novel.dart';
import 'package:built_collection/built_collection.dart';
import 'package:novel_api/src/model/chapter.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'novel_with_chapters.g.dart';

/// Novel with chapters response schema.
///
/// Properties:
/// * [novel] 
/// * [chapters] 
@BuiltValue()
abstract class NovelWithChapters implements Built<NovelWithChapters, NovelWithChaptersBuilder> {
  @BuiltValueField(wireName: r'novel')
  Novel get novel;

  @BuiltValueField(wireName: r'chapters')
  BuiltList<Chapter> get chapters;

  NovelWithChapters._();

  factory NovelWithChapters([void updates(NovelWithChaptersBuilder b)]) = _$NovelWithChapters;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(NovelWithChaptersBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<NovelWithChapters> get serializer => _$NovelWithChaptersSerializer();
}

class _$NovelWithChaptersSerializer implements PrimitiveSerializer<NovelWithChapters> {
  @override
  final Iterable<Type> types = const [NovelWithChapters, _$NovelWithChapters];

  @override
  final String wireName = r'NovelWithChapters';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    NovelWithChapters object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'novel';
    yield serializers.serialize(
      object.novel,
      specifiedType: const FullType(Novel),
    );
    yield r'chapters';
    yield serializers.serialize(
      object.chapters,
      specifiedType: const FullType(BuiltList, [FullType(Chapter)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    NovelWithChapters object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required NovelWithChaptersBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'novel':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Novel),
          ) as Novel;
          result.novel.replace(valueDes);
          break;
        case r'chapters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Chapter)]),
          ) as BuiltList<Chapter>;
          result.chapters.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  NovelWithChapters deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = NovelWithChaptersBuilder();
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

