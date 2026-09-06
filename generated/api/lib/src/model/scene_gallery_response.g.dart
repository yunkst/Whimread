// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_gallery_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SceneGalleryResponse extends SceneGalleryResponse {
  @override
  final String taskId;
  @override
  final BuiltList<ImageWithModel> images;
  @override
  final String? modelName;
  @override
  final int? modelWidth;
  @override
  final int? modelHeight;

  factory _$SceneGalleryResponse(
          [void Function(SceneGalleryResponseBuilder)? updates]) =>
      (SceneGalleryResponseBuilder()..update(updates))._build();

  _$SceneGalleryResponse._(
      {required this.taskId,
      required this.images,
      this.modelName,
      this.modelWidth,
      this.modelHeight})
      : super._();
  @override
  SceneGalleryResponse rebuild(
          void Function(SceneGalleryResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SceneGalleryResponseBuilder toBuilder() =>
      SceneGalleryResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SceneGalleryResponse &&
        taskId == other.taskId &&
        images == other.images &&
        modelName == other.modelName &&
        modelWidth == other.modelWidth &&
        modelHeight == other.modelHeight;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, taskId.hashCode);
    _$hash = $jc(_$hash, images.hashCode);
    _$hash = $jc(_$hash, modelName.hashCode);
    _$hash = $jc(_$hash, modelWidth.hashCode);
    _$hash = $jc(_$hash, modelHeight.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SceneGalleryResponse')
          ..add('taskId', taskId)
          ..add('images', images)
          ..add('modelName', modelName)
          ..add('modelWidth', modelWidth)
          ..add('modelHeight', modelHeight))
        .toString();
  }
}

class SceneGalleryResponseBuilder
    implements Builder<SceneGalleryResponse, SceneGalleryResponseBuilder> {
  _$SceneGalleryResponse? _$v;

  String? _taskId;
  String? get taskId => _$this._taskId;
  set taskId(String? taskId) => _$this._taskId = taskId;

  ListBuilder<ImageWithModel>? _images;
  ListBuilder<ImageWithModel> get images =>
      _$this._images ??= ListBuilder<ImageWithModel>();
  set images(ListBuilder<ImageWithModel>? images) => _$this._images = images;

  String? _modelName;
  String? get modelName => _$this._modelName;
  set modelName(String? modelName) => _$this._modelName = modelName;

  int? _modelWidth;
  int? get modelWidth => _$this._modelWidth;
  set modelWidth(int? modelWidth) => _$this._modelWidth = modelWidth;

  int? _modelHeight;
  int? get modelHeight => _$this._modelHeight;
  set modelHeight(int? modelHeight) => _$this._modelHeight = modelHeight;

  SceneGalleryResponseBuilder() {
    SceneGalleryResponse._defaults(this);
  }

  SceneGalleryResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _taskId = $v.taskId;
      _images = $v.images.toBuilder();
      _modelName = $v.modelName;
      _modelWidth = $v.modelWidth;
      _modelHeight = $v.modelHeight;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SceneGalleryResponse other) {
    _$v = other as _$SceneGalleryResponse;
  }

  @override
  void update(void Function(SceneGalleryResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SceneGalleryResponse build() => _build();

  _$SceneGalleryResponse _build() {
    _$SceneGalleryResponse _$result;
    try {
      _$result = _$v ??
          _$SceneGalleryResponse._(
            taskId: BuiltValueNullFieldError.checkNotNull(
                taskId, r'SceneGalleryResponse', 'taskId'),
            images: images.build(),
            modelName: modelName,
            modelWidth: modelWidth,
            modelHeight: modelHeight,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'images';
        images.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SceneGalleryResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
