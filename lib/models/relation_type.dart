import 'package:flutter/material.dart';

/// 人物关系类型(封闭枚举)。
///
/// 每个值带 [forward](source 视角词)与 [reverse](target 视角词)。
/// 关系 (A→B, type) 表示"A 是 B 的 [forward]";A 的出度显示 forward,
/// B 的入度显示 reverse。对称类型 forward == reverse。
///
/// 完整 109 个值的权威来源:
/// docs/superpowers/specs/relationship-types-catalog.md
enum RelationType {
  // ─── 1. 血亲·直系(暗红系)──────────────────────────────────
  parentChild('父母', '子女', Color(0xFF8B0000), symmetric: false),
  grandparentGrandchild('祖父母', '孙辈', Color(0xFFA52A2A), symmetric: false),
  greatGrandparentDescendant('曾祖/高祖', '曾孙/玄孙', Color(0xFFA0522D),
      symmetric: false),

  // ─── 2. 血亲·旁系与义亲(棕红系)────────────────────────────
  sibling('兄弟姐妹', '兄弟姐妹', Color(0xFFB22222), symmetric: true),
  halfSibling('同父异母/同母异父', '同父异母/同母异父', Color(0xFFCD5C5C),
      symmetric: true),
  cousin('堂表兄弟姐妹', '堂表兄弟姐妹', Color(0xFFB22222), symmetric: true),
  uncleAuntNephew('叔伯姑舅姨', '侄甥', Color(0xFFA0522D), symmetric: false),
  adoptiveParentChild('养父母', '养子女', Color(0xFF8B4513), symmetric: false),
  swornFamily('义父母', '义子女', Color(0xFF8B4513), symmetric: false),
  wetNurseChild('乳母', '乳子', Color(0xFF8B4513), symmetric: false),

  // ─── 3. 姻亲与再婚(玫红系)──────────────────────────────────
  spouse('配偶', '配偶', Color(0xFFC71585), symmetric: true),
  concubine('妾室', '主君', Color(0xFFDB7093), symmetric: false),
  coWife('同室姐妹', '同室姐妹', Color(0xFFDB7093), symmetric: true),
  parentInLaw('岳父母/公婆', '女婿/儿媳', Color(0xFFB03060), symmetric: false),
  siblingInLaw('姻亲兄弟姐妹', '姻亲兄弟姐妹', Color(0xFFB03060),
      symmetric: true),
  stepParentChild('继父母', '继子女', Color(0xFF8B4513), symmetric: false),
  stepSibling('继兄弟姐妹', '继兄弟姐妹', Color(0xFF8B4513), symmetric: true),

  // ─── 4. 婚恋情感(粉红系)────────────────────────────────────
  lover('恋人', '恋人', Color(0xFFFF69B4), symmetric: true),
  fiance('未婚夫妻', '未婚夫妻', Color(0xFFFF1493), symmetric: true),
  exLover('前任', '前任', Color(0xFFFFB6C1), symmetric: true),
  childhoodSweetheart('青梅竹马', '青梅竹马', Color(0xFFFF69B4),
      symmetric: true),
  secretAdmirer('暗恋者', '被暗恋者', Color(0xFFFFC0CB), symmetric: false),
  unrequitedLove('苦恋者', '被苦恋者', Color(0xFFFFC0CB), symmetric: false),
  mistress('外室/情妇', '包养者', Color(0xFFC71585), symmetric: false),
  rivalInLove('情敌', '情敌', Color(0xFFFF6347), symmetric: true),

  // ─── 5. 师徒与传承(紫色系)──────────────────────────────────
  masterDisciple('师父', '徒弟', Color(0xFF663399), symmetric: false),
  grandmasterDisciple('师祖/太师祖', '徒孙/徒曾孙', Color(0xFF6A5ACD),
      symmetric: false),
  sectElderJunior('师叔伯/师伯', '师侄', Color(0xFF7B68EE), symmetric: false),
  fellowDisciple('同门师兄弟姐妹', '同门师兄弟姐妹', Color(0xFF6495ED),
      symmetric: true),
  sameSectDisciple('同门/同宗', '同门/同宗', Color(0xFF6495ED), symmetric: true),
  teacherStudent('老师', '学生', Color(0xFF9370DB), symmetric: false),
  mentorMentee('引路人/导师', '受指点者', Color(0xFF9370DB), symmetric: false),
  inheritorPredecessor('衣钵传人', '前辈/传功者', Color(0xFF8A2BE2),
      symmetric: false),

  // ─── 6. 同窗同侪(蓝色系)────────────────────────────────────
  classmate('同学', '同学', Color(0xFF4169E1), symmetric: true),
  schoolmate('校友', '校友', Color(0xFF4682B4), symmetric: true),
  seniorJuniorStudent('学长/学姐', '学弟/学妹', Color(0xFF5F9EA0),
      symmetric: false),
  fellowExamCandidate('同年/同榜', '同年/同榜', Color(0xFF4682B4),
      symmetric: true),
  colleague('同事', '同事', Color(0xFF1E90FF), symmetric: true),
  comradeInArms('战友/同袍', '战友/同袍', Color(0xFF0000CD), symmetric: true),
  teammate('队友', '队友', Color(0xFF00BFFF), symmetric: true),
  companion('同伴/同行者', '同伴/同行者', Color(0xFF87CEEB), symmetric: true),

  // ─── 7. 朋友知己(蓝/金系)───────────────────────────────────
  friend('朋友', '朋友', Color(0xFF4169E1), symmetric: true),
  closeFriend('知己/挚友', '知己/挚友', Color(0xFF191970), symmetric: true),
  swornSibling('结义兄弟/姐妹', '结义兄弟/姐妹', Color(0xFFDAA520),
      symmetric: true),
  crossGenerationFriend('忘年交', '忘年交', Color(0xFF4682B4), symmetric: true),

  // ─── 8. 权力从属(金/橙系)───────────────────────────────────
  monarchSubject('君/陛下', '臣', Color(0xFFFFD700), symmetric: false),
  lordRetainer('主公', '部属/门客/谋士', Color(0xFFDAA520), symmetric: false),
  sectLeaderMember('掌门/门主/帮主', '门人/帮众', Color(0xFFB8860B),
      symmetric: false),
  superiorSubordinate('上司', '下属', Color(0xFFCD853F), symmetric: false),
  masterServant('主人', '仆人/奴婢', Color(0xFF8B4513), symmetric: false),
  employerEmployee('雇主', '雇员', Color(0xFF8B4513), symmetric: false),
  employerMercenary('雇主', '佣兵/猎兵', Color(0xFFA0522D), symmetric: false),
  masterSlave('主人', '奴隶', Color(0xFF5C2E00), symmetric: false),
  liegeVassal('领主', '封臣', Color(0xFFB8860B), symmetric: false),

  // ─── 9. 恩义仇怨(绿/暗红系)─────────────────────────────────
  benefactorBeneficiary('恩人', '受恩者', Color(0xFF228B22), symmetric: false),
  saviorSaved('救命恩人', '被救者', Color(0xFF006400), symmetric: false),
  creditorDebtor('债主', '欠债人', Color(0xFF2E8B57), symmetric: false),
  enemy('敌人', '敌人', Color(0xFF800000), symmetric: true),
  swornEnemy('死敌/仇敌', '死敌/仇敌', Color(0xFF8B0000), symmetric: true),
  bloodFeudEnemy('血仇', '血仇', Color(0xFF5C0000), symmetric: true),
  betrayerBetrayed('背叛者', '被背叛者', Color(0xFFA52A2A), symmetric: false),

  // ─── 10. 敌对竞争(灰色系)───────────────────────────────────
  rival('对手', '对手', Color(0xFF696969), symmetric: true),
  competitor('竞争者', '竞争者', Color(0xFF808080), symmetric: true),
  frienemy('亦敌亦友', '亦敌亦友', Color(0xFF708090), symmetric: true),
  nemesis('宿敌', '宿敌', Color(0xFF2F4F4F), symmetric: true),

  // ─── 11. 契约羁绊(青色系)───────────────────────────────────
  contractPartner('契约伙伴', '契约伙伴', Color(0xFF008B8B), symmetric: true),
  bloodPactSibling('血盟兄弟', '血盟兄弟', Color(0xFF2F4F4F), symmetric: true),
  soulContractMaster('主人(魂契)', '魂仆/魂奴', Color(0xFF2F2F4F),
      symmetric: false),
  masterContractBeast('主人', '契约兽/灵兽', Color(0xFF008080),
      symmetric: false),
  beastPartner('灵兽契约伙伴', '灵兽契约伙伴', Color(0xFF20B2AA),
      symmetric: true),
  summonerSummon('召唤师', '召唤物/召唤兽', Color(0xFF008080), symmetric: false),
  familiarMaster('主人', '使魔', Color(0xFF5F9EA0), symmetric: false),

  // ─── 12. 修仙玄幻特殊(紫金系)───────────────────────────────
  daoCompanion('道侣', '道侣', Color(0xFF9370DB), symmetric: true),
  dualCultivationPartner('双修伴侣', '双修伴侣', Color(0xFF8B008B),
      symmetric: true),
  avatarMainBody('分身', '本体', Color(0xFF9B30FF), symmetric: false),
  innerDemonHost('心魔', '宿主', Color(0xFF4B0082), symmetric: false),
  symbiote('共生体', '共生体', Color(0xFF6A5ACD), symmetric: true),
  bloodlineAncestorDescendant('血脉先祖', '血脉后裔', Color(0xFF8A2BE2),
      symmetric: false),
  artifactSpiritMaster('主人', '器灵/剑灵', Color(0xFF7B68EE),
      symmetric: false),
  possessorHost('夺舍者', '原主/被夺舍者', Color(0xFF4B0082),
      symmetric: false),

  // ─── 13. 宗教信仰(圣金系)───────────────────────────────────
  deityBeliever('神明', '信徒', Color(0xFFFFD700), symmetric: false),
  deityChosen('眷顾之神', '神眷者/神选者', Color(0xFFDAA520),
      symmetric: false),
  cultLeaderBeliever('教主', '教徒', Color(0xFFB8860B), symmetric: false),
  prophetFollowers('先知/圣女', '信众', Color(0xFFDAA520), symmetric: false),

  // ─── 14. 科幻与系统流特殊(冷蓝/银系)────────────────────────
  creatorCreation('创造者', '造物/被造者', Color(0xFF4169E1), symmetric: false),
  linkedMinds('同步者/链接者', '同步者/链接者', Color(0xFF4682B4),
      symmetric: true),
  aiOwner('主人', 'AI 伴侣', Color(0xFF5F9EA0), symmetric: false),
  systemHost('系统', '宿主/绑定者', Color(0xFF9370DB), symmetric: false),
  puppeteerPuppet('操纵者', '傀儡', Color(0xFF483D8B), symmetric: false),

  // ─── 15. 地缘与其他(浅蓝系)─────────────────────────────────
  hometownTie('同乡', '同乡', Color(0xFF4682B4), symmetric: true),
  neighbor('邻居', '邻居', Color(0xFF87CEEB), symmetric: true),
  doctorPatient('医者', '病患', Color(0xFF5F9EA0), symmetric: false),
  guildLeaderMember('会长/团长', '会员/团员', Color(0xFF4682B4),
      symmetric: false),
  factionAlly('同阵营/同道', '同阵营/同道', Color(0xFF4682B4),
      symmetric: true),

  // ─── 16. 转世宿命(紫金系)───────────────────────────────────
  reincarnationPredecessor('前世', '今生', Color(0xFF9B30FF),
      symmetric: false),
  fatedLover('天定姻缘', '天定姻缘', Color(0xFFC71585), symmetric: true),
  fatedEnemy('命中宿敌', '命中宿敌', Color(0xFF4B0082), symmetric: true),

  // ─── 17. 情色·奴役·占有(成人向,暗色系,无开关)──────────────
  sexSlaveMaster('性奴/肉奴', '主人', Color(0xFF4B0082), symmetric: false),
  paramour('情人', '情人', Color(0xFF722F37), symmetric: true),
  maleFavorite('面首/男宠', '女主/主母', Color(0xFF722F37), symmetric: false),
  cauldronCultivator('炉鼎/鼎炉', '采补者', Color(0xFF4B0082),
      symmetric: false),
  forbiddenPossession('禁脔', '占有者', Color(0xFF5C0000), symmetric: false),
  playthingPlayer('玩物', '玩弄者', Color(0xFF3C1414), symmetric: false),
  captiveCaptor('被囚禁者', '囚禁者', Color(0xFF1C1C1C), symmetric: false),
  preyPredator('猎物', '掠夺者', Color(0xFF1C1C1C), symmetric: false),
  masterSlaveSm('主(S)', '奴(M)', Color(0xFF4B0082), symmetric: false),
  trainerTrainee('调教者', '被调教者', Color(0xFF4B0082), symmetric: false),
  sharedPartner('共有对象', '共有者', Color(0xFF5C0000), symmetric: false),
  usurperVictim('强占者', '被强占者', Color(0xFF5C0000), symmetric: false),
  ;

  final String forward;
  final String reverse;
  final Color color;
  final bool symmetric;

  const RelationType(this.forward, this.reverse, this.color,
      {required this.symmetric});

  /// 按方向返回词条:[isSource] 为 true 返回正向词,否则反向词。
  String labelFor({required bool isSource}) =>
      isSource ? forward : reverse;
}
