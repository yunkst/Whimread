// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_status_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$VideoStatusResponse extends VideoStatusResponse {
  @override
  final String imgName;
  @override
  final bool hasVideo;
  @override
  final String? videoStatus;
  @override
  final String? videoFilename;

  factory _$VideoStatusResponse(
          [void Function(VideoStatusResponseBuilder)? updates]) =>
      (VideoStatusResponseBuilder()..update(updates))._build();

  _$VideoStatusResponse._(
      {required this.imgName,
      required this.hasVideo,
      this.videoStatus,
      this.videoFilename})
      : super._();
  @override
  VideoStatusResponse rebuild(
          void Function(VideoStatusResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  VideoStatusResponseBuilder toBuilder() =>
      VideoStatusResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is VideoStatusResponse &&
        imgName == other.imgName &&
        hasVideo == other.hasVideo &&
        videoStatus == other.videoStatus &&
        videoFilename == other.videoFilename;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, imgName.hashCode);
    _$hash = $jc(_$hash, hasVideo.hashCode);
    _$hash = $jc(_$hash, videoStatus.hashCode);
    _$hash = $jc(_$hash, videoFilename.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'VideoStatusResponse')
          ..add('imgName', imgName)
          ..add('hasVideo', hasVideo)
          ..add('videoStatus', videoStatus)
          ..add('videoFilename', videoFilename))
        .toString();
  }
}

class VideoStatusResponseBuilder
    implements Builder<VideoStatusResponse, VideoStatusResponseBuilder> {
  _$VideoStatusResponse? _$v;

  String? _imgName;
  String? get imgName => _$this._imgName;
  set imgName(String? imgName) => _$this._imgName = imgName;

  bool? _hasVideo;
  bool? get hasVideo => _$this._hasVideo;
  set hasVideo(bool? hasVideo) => _$this._hasVideo = hasVideo;

  String? _videoStatus;
  String? get videoStatus => _$this._videoStatus;
  set videoStatus(String? videoStatus) => _$this._videoStatus = videoStatus;

  String? _videoFilename;
  String? get videoFilename => _$this._videoFilename;
  set videoFilename(String? videoFilename) =>
      _$this._videoFilename = videoFilename;

  VideoStatusResponseBuilder() {
    VideoStatusResponse._defaults(this);
  }

  VideoStatusResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _imgName = $v.imgName;
      _hasVideo = $v.hasVideo;
      _videoStatus = $v.videoStatus;
      _videoFilename = $v.videoFilename;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(VideoStatusResponse other) {
    _$v = other as _$VideoStatusResponse;
  }

  @override
  void update(void Function(VideoStatusResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  VideoStatusResponse build() => _build();

  _$VideoStatusResponse _build() {
    final _$result = _$v ??
        _$VideoStatusResponse._(
          imgName: BuiltValueNullFieldError.checkNotNull(
              imgName, r'VideoStatusResponse', 'imgName'),
          hasVideo: BuiltValueNullFieldError.checkNotNull(
              hasVideo, r'VideoStatusResponse', 'hasVideo'),
          videoStatus: videoStatus,
          videoFilename: videoFilename,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
