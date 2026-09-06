// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role_info.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$RoleInfo extends RoleInfo {
  @override
  final int id;
  @override
  final String name;
  @override
  final String? gender;
  @override
  final int? age;
  @override
  final String? occupation;
  @override
  final String? personality;
  @override
  final String? appearanceFeatures;
  @override
  final String? bodyType;
  @override
  final String? clothingStyle;
  @override
  final String? backgroundStory;
  @override
  final String? facePrompts;
  @override
  final String? bodyPrompts;

  factory _$RoleInfo([void Function(RoleInfoBuilder)? updates]) =>
      (RoleInfoBuilder()..update(updates))._build();

  _$RoleInfo._(
      {required this.id,
      required this.name,
      this.gender,
      this.age,
      this.occupation,
      this.personality,
      this.appearanceFeatures,
      this.bodyType,
      this.clothingStyle,
      this.backgroundStory,
      this.facePrompts,
      this.bodyPrompts})
      : super._();
  @override
  RoleInfo rebuild(void Function(RoleInfoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  RoleInfoBuilder toBuilder() => RoleInfoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is RoleInfo &&
        id == other.id &&
        name == other.name &&
        gender == other.gender &&
        age == other.age &&
        occupation == other.occupation &&
        personality == other.personality &&
        appearanceFeatures == other.appearanceFeatures &&
        bodyType == other.bodyType &&
        clothingStyle == other.clothingStyle &&
        backgroundStory == other.backgroundStory &&
        facePrompts == other.facePrompts &&
        bodyPrompts == other.bodyPrompts;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, gender.hashCode);
    _$hash = $jc(_$hash, age.hashCode);
    _$hash = $jc(_$hash, occupation.hashCode);
    _$hash = $jc(_$hash, personality.hashCode);
    _$hash = $jc(_$hash, appearanceFeatures.hashCode);
    _$hash = $jc(_$hash, bodyType.hashCode);
    _$hash = $jc(_$hash, clothingStyle.hashCode);
    _$hash = $jc(_$hash, backgroundStory.hashCode);
    _$hash = $jc(_$hash, facePrompts.hashCode);
    _$hash = $jc(_$hash, bodyPrompts.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'RoleInfo')
          ..add('id', id)
          ..add('name', name)
          ..add('gender', gender)
          ..add('age', age)
          ..add('occupation', occupation)
          ..add('personality', personality)
          ..add('appearanceFeatures', appearanceFeatures)
          ..add('bodyType', bodyType)
          ..add('clothingStyle', clothingStyle)
          ..add('backgroundStory', backgroundStory)
          ..add('facePrompts', facePrompts)
          ..add('bodyPrompts', bodyPrompts))
        .toString();
  }
}

class RoleInfoBuilder implements Builder<RoleInfo, RoleInfoBuilder> {
  _$RoleInfo? _$v;

  int? _id;
  int? get id => _$this._id;
  set id(int? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _gender;
  String? get gender => _$this._gender;
  set gender(String? gender) => _$this._gender = gender;

  int? _age;
  int? get age => _$this._age;
  set age(int? age) => _$this._age = age;

  String? _occupation;
  String? get occupation => _$this._occupation;
  set occupation(String? occupation) => _$this._occupation = occupation;

  String? _personality;
  String? get personality => _$this._personality;
  set personality(String? personality) => _$this._personality = personality;

  String? _appearanceFeatures;
  String? get appearanceFeatures => _$this._appearanceFeatures;
  set appearanceFeatures(String? appearanceFeatures) =>
      _$this._appearanceFeatures = appearanceFeatures;

  String? _bodyType;
  String? get bodyType => _$this._bodyType;
  set bodyType(String? bodyType) => _$this._bodyType = bodyType;

  String? _clothingStyle;
  String? get clothingStyle => _$this._clothingStyle;
  set clothingStyle(String? clothingStyle) =>
      _$this._clothingStyle = clothingStyle;

  String? _backgroundStory;
  String? get backgroundStory => _$this._backgroundStory;
  set backgroundStory(String? backgroundStory) =>
      _$this._backgroundStory = backgroundStory;

  String? _facePrompts;
  String? get facePrompts => _$this._facePrompts;
  set facePrompts(String? facePrompts) => _$this._facePrompts = facePrompts;

  String? _bodyPrompts;
  String? get bodyPrompts => _$this._bodyPrompts;
  set bodyPrompts(String? bodyPrompts) => _$this._bodyPrompts = bodyPrompts;

  RoleInfoBuilder() {
    RoleInfo._defaults(this);
  }

  RoleInfoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _gender = $v.gender;
      _age = $v.age;
      _occupation = $v.occupation;
      _personality = $v.personality;
      _appearanceFeatures = $v.appearanceFeatures;
      _bodyType = $v.bodyType;
      _clothingStyle = $v.clothingStyle;
      _backgroundStory = $v.backgroundStory;
      _facePrompts = $v.facePrompts;
      _bodyPrompts = $v.bodyPrompts;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(RoleInfo other) {
    _$v = other as _$RoleInfo;
  }

  @override
  void update(void Function(RoleInfoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  RoleInfo build() => _build();

  _$RoleInfo _build() {
    final _$result = _$v ??
        _$RoleInfo._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'RoleInfo', 'id'),
          name:
              BuiltValueNullFieldError.checkNotNull(name, r'RoleInfo', 'name'),
          gender: gender,
          age: age,
          occupation: occupation,
          personality: personality,
          appearanceFeatures: appearanceFeatures,
          bodyType: bodyType,
          clothingStyle: clothingStyle,
          backgroundStory: backgroundStory,
          facePrompts: facePrompts,
          bodyPrompts: bodyPrompts,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
