//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'role_card_task_status_response.g.dart';

/// 人物卡任务状态响应模式.
///
/// Properties:
/// * [taskId] - 任务ID
/// * [roleId] - 人物卡ID
/// * [status] - 任务状态: pending/running/completed/failed
/// * [totalPrompts] - 生成的提示词数量
/// * [generatedImages] - 成功生成的图片数量
/// * [resultMessage] 
/// * [errorMessage] 
/// * [createdAt] - 创建时间
/// * [startedAt] 
/// * [completedAt] 
/// * [progressPercentage] - 进度百分比
@BuiltValue()
abstract class RoleCardTaskStatusResponse implements Built<RoleCardTaskStatusResponse, RoleCardTaskStatusResponseBuilder> {
  /// 任务ID
  @BuiltValueField(wireName: r'task_id')
  int get taskId;

  /// 人物卡ID
  @BuiltValueField(wireName: r'role_id')
  String get roleId;

  /// 任务状态: pending/running/completed/failed
  @BuiltValueField(wireName: r'status')
  String get status;

  /// 生成的提示词数量
  @BuiltValueField(wireName: r'total_prompts')
  int get totalPrompts;

  /// 成功生成的图片数量
  @BuiltValueField(wireName: r'generated_images')
  int get generatedImages;

  @BuiltValueField(wireName: r'result_message')
  String? get resultMessage;

  @BuiltValueField(wireName: r'error_message')
  String? get errorMessage;

  /// 创建时间
  @BuiltValueField(wireName: r'created_at')
  String get createdAt;

  @BuiltValueField(wireName: r'started_at')
  String? get startedAt;

  @BuiltValueField(wireName: r'completed_at')
  String? get completedAt;

  /// 进度百分比
  @BuiltValueField(wireName: r'progress_percentage')
  num get progressPercentage;

  RoleCardTaskStatusResponse._();

  factory RoleCardTaskStatusResponse([void updates(RoleCardTaskStatusResponseBuilder b)]) = _$RoleCardTaskStatusResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RoleCardTaskStatusResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RoleCardTaskStatusResponse> get serializer => _$RoleCardTaskStatusResponseSerializer();
}

class _$RoleCardTaskStatusResponseSerializer implements PrimitiveSerializer<RoleCardTaskStatusResponse> {
  @override
  final Iterable<Type> types = const [RoleCardTaskStatusResponse, _$RoleCardTaskStatusResponse];

  @override
  final String wireName = r'RoleCardTaskStatusResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RoleCardTaskStatusResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'task_id';
    yield serializers.serialize(
      object.taskId,
      specifiedType: const FullType(int),
    );
    yield r'role_id';
    yield serializers.serialize(
      object.roleId,
      specifiedType: const FullType(String),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(String),
    );
    yield r'total_prompts';
    yield serializers.serialize(
      object.totalPrompts,
      specifiedType: const FullType(int),
    );
    yield r'generated_images';
    yield serializers.serialize(
      object.generatedImages,
      specifiedType: const FullType(int),
    );
    if (object.resultMessage != null) {
      yield r'result_message';
      yield serializers.serialize(
        object.resultMessage,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.errorMessage != null) {
      yield r'error_message';
      yield serializers.serialize(
        object.errorMessage,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(String),
    );
    if (object.startedAt != null) {
      yield r'started_at';
      yield serializers.serialize(
        object.startedAt,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.completedAt != null) {
      yield r'completed_at';
      yield serializers.serialize(
        object.completedAt,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'progress_percentage';
    yield serializers.serialize(
      object.progressPercentage,
      specifiedType: const FullType(num),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RoleCardTaskStatusResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RoleCardTaskStatusResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'task_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.taskId = valueDes;
          break;
        case r'role_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.roleId = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.status = valueDes;
          break;
        case r'total_prompts':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalPrompts = valueDes;
          break;
        case r'generated_images':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.generatedImages = valueDes;
          break;
        case r'result_message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.resultMessage = valueDes;
          break;
        case r'error_message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.errorMessage = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.createdAt = valueDes;
          break;
        case r'started_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.startedAt = valueDes;
          break;
        case r'completed_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.completedAt = valueDes;
          break;
        case r'progress_percentage':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(num),
          ) as num;
          result.progressPercentage = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RoleCardTaskStatusResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RoleCardTaskStatusResponseBuilder();
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

