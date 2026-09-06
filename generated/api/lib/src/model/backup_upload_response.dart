//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'backup_upload_response.g.dart';

/// 数据库备份上传响应模式.
///
/// Properties:
/// * [filename] - 原始文件名
/// * [storedPath] - 存储路径
/// * [fileSize] - 文件大小(字节)
/// * [uploadedAt] - 上传时间(ISO格式)
/// * [storedName] - 存储文件名
@BuiltValue()
abstract class BackupUploadResponse implements Built<BackupUploadResponse, BackupUploadResponseBuilder> {
  /// 原始文件名
  @BuiltValueField(wireName: r'filename')
  String get filename;

  /// 存储路径
  @BuiltValueField(wireName: r'stored_path')
  String get storedPath;

  /// 文件大小(字节)
  @BuiltValueField(wireName: r'file_size')
  int get fileSize;

  /// 上传时间(ISO格式)
  @BuiltValueField(wireName: r'uploaded_at')
  String get uploadedAt;

  /// 存储文件名
  @BuiltValueField(wireName: r'stored_name')
  String get storedName;

  BackupUploadResponse._();

  factory BackupUploadResponse([void updates(BackupUploadResponseBuilder b)]) = _$BackupUploadResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BackupUploadResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BackupUploadResponse> get serializer => _$BackupUploadResponseSerializer();
}

class _$BackupUploadResponseSerializer implements PrimitiveSerializer<BackupUploadResponse> {
  @override
  final Iterable<Type> types = const [BackupUploadResponse, _$BackupUploadResponse];

  @override
  final String wireName = r'BackupUploadResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BackupUploadResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'filename';
    yield serializers.serialize(
      object.filename,
      specifiedType: const FullType(String),
    );
    yield r'stored_path';
    yield serializers.serialize(
      object.storedPath,
      specifiedType: const FullType(String),
    );
    yield r'file_size';
    yield serializers.serialize(
      object.fileSize,
      specifiedType: const FullType(int),
    );
    yield r'uploaded_at';
    yield serializers.serialize(
      object.uploadedAt,
      specifiedType: const FullType(String),
    );
    yield r'stored_name';
    yield serializers.serialize(
      object.storedName,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    BackupUploadResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BackupUploadResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'filename':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.filename = valueDes;
          break;
        case r'stored_path':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.storedPath = valueDes;
          break;
        case r'file_size':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.fileSize = valueDes;
          break;
        case r'uploaded_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.uploadedAt = valueDes;
          break;
        case r'stored_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.storedName = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  BackupUploadResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BackupUploadResponseBuilder();
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

