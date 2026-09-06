//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'app_version_response.g.dart';

/// APP版本信息响应模式.
///
/// Properties:
/// * [version] - 版本号
/// * [versionCode] - 版本递增码
/// * [downloadUrl] - 下载URL
/// * [fileSize] - 文件大小(字节)
/// * [changelog] 
/// * [forceUpdate] - 是否强制更新
/// * [createdAt] - 发布时间
@BuiltValue()
abstract class AppVersionResponse implements Built<AppVersionResponse, AppVersionResponseBuilder> {
  /// 版本号
  @BuiltValueField(wireName: r'version')
  String get version;

  /// 版本递增码
  @BuiltValueField(wireName: r'version_code')
  int get versionCode;

  /// 下载URL
  @BuiltValueField(wireName: r'download_url')
  String get downloadUrl;

  /// 文件大小(字节)
  @BuiltValueField(wireName: r'file_size')
  int get fileSize;

  @BuiltValueField(wireName: r'changelog')
  String? get changelog;

  /// 是否强制更新
  @BuiltValueField(wireName: r'force_update')
  bool? get forceUpdate;

  /// 发布时间
  @BuiltValueField(wireName: r'created_at')
  String get createdAt;

  AppVersionResponse._();

  factory AppVersionResponse([void updates(AppVersionResponseBuilder b)]) = _$AppVersionResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AppVersionResponseBuilder b) => b
      ..forceUpdate = false;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppVersionResponse> get serializer => _$AppVersionResponseSerializer();
}

class _$AppVersionResponseSerializer implements PrimitiveSerializer<AppVersionResponse> {
  @override
  final Iterable<Type> types = const [AppVersionResponse, _$AppVersionResponse];

  @override
  final String wireName = r'AppVersionResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppVersionResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(String),
    );
    yield r'version_code';
    yield serializers.serialize(
      object.versionCode,
      specifiedType: const FullType(int),
    );
    yield r'download_url';
    yield serializers.serialize(
      object.downloadUrl,
      specifiedType: const FullType(String),
    );
    yield r'file_size';
    yield serializers.serialize(
      object.fileSize,
      specifiedType: const FullType(int),
    );
    if (object.changelog != null) {
      yield r'changelog';
      yield serializers.serialize(
        object.changelog,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.forceUpdate != null) {
      yield r'force_update';
      yield serializers.serialize(
        object.forceUpdate,
        specifiedType: const FullType(bool),
      );
    }
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AppVersionResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AppVersionResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.version = valueDes;
          break;
        case r'version_code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.versionCode = valueDes;
          break;
        case r'download_url':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.downloadUrl = valueDes;
          break;
        case r'file_size':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.fileSize = valueDes;
          break;
        case r'changelog':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.changelog = valueDes;
          break;
        case r'force_update':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.forceUpdate = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AppVersionResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AppVersionResponseBuilder();
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

