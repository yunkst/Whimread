//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'workflow_info.g.dart';

/// 工作流信息模式.
///
/// Properties:
/// * [title] - 工作流标题
/// * [description] - 工作流描述
/// * [path] 
/// * [width] 
/// * [height] 
/// * [isDefault] - 是否为默认模型
@BuiltValue()
abstract class WorkflowInfo implements Built<WorkflowInfo, WorkflowInfoBuilder> {
  /// 工作流标题
  @BuiltValueField(wireName: r'title')
  String get title;

  /// 工作流描述
  @BuiltValueField(wireName: r'description')
  String get description;

  @BuiltValueField(wireName: r'path')
  String? get path;

  @BuiltValueField(wireName: r'width')
  int? get width;

  @BuiltValueField(wireName: r'height')
  int? get height;

  /// 是否为默认模型
  @BuiltValueField(wireName: r'is_default')
  bool? get isDefault;

  WorkflowInfo._();

  factory WorkflowInfo([void updates(WorkflowInfoBuilder b)]) = _$WorkflowInfo;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WorkflowInfoBuilder b) => b
      ..isDefault = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<WorkflowInfo> get serializer => _$WorkflowInfoSerializer();
}

class _$WorkflowInfoSerializer implements PrimitiveSerializer<WorkflowInfo> {
  @override
  final Iterable<Type> types = const [WorkflowInfo, _$WorkflowInfo];

  @override
  final String wireName = r'WorkflowInfo';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WorkflowInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'title';
    yield serializers.serialize(
      object.title,
      specifiedType: const FullType(String),
    );
    yield r'description';
    yield serializers.serialize(
      object.description,
      specifiedType: const FullType(String),
    );
    if (object.path != null) {
      yield r'path';
      yield serializers.serialize(
        object.path,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.width != null) {
      yield r'width';
      yield serializers.serialize(
        object.width,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.height != null) {
      yield r'height';
      yield serializers.serialize(
        object.height,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.isDefault != null) {
      yield r'is_default';
      yield serializers.serialize(
        object.isDefault,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    WorkflowInfo object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WorkflowInfoBuilder result,
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
        case r'description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.description = valueDes;
          break;
        case r'path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.path = valueDes;
          break;
        case r'width':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.width = valueDes;
          break;
        case r'height':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.height = valueDes;
          break;
        case r'is_default':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isDefault = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WorkflowInfo deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WorkflowInfoBuilder();
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

