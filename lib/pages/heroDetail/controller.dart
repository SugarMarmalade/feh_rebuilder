import 'package:cloud_db/cloud_db.dart';
import 'package:feh_rebuilder/data_service.dart';
import 'package:feh_rebuilder/models/build_share/build_table.dart';

import 'package:feh_rebuilder/models/person/skills.dart';
import 'package:feh_rebuilder/models/personBuild/person_build.dart';
import 'package:feh_rebuilder/models/person/person.dart';
import 'package:feh_rebuilder/models/person/stats.dart';
import 'package:feh_rebuilder/models/skill/skill.dart';
import 'package:feh_rebuilder/pages/heroDetail/widgets/custom_btn.dart';
import 'package:feh_rebuilder/pages/heroDetail/widgets/tag_choose_body.dart';
import 'package:feh_rebuilder/pages/home/subview/favorite_controller.dart';
import 'package:feh_rebuilder/utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:math' as m;

import 'widgets/share_widget.dart';

class HeroDetailController extends GetxController {
  /// [person hero ,list<skill?> heroSkills ,List<Map<Skill, Skill>> weaponRefine]
  late PersonBuild build = Get.arguments;

  late Person hero;

  /// 技能栏有6+2 (圣印，祝福)，+1（专武）
  List<Skill?> heroSkills = [];
  List<Skill?> origHeroSkills = [];

  DataService data = Get.find<DataService>();

  /// 初始的武器炼成技能
  late List<Map<Skill, Skill>> origWeaponRefine;

  // 神装
  bool isResplendent = false;
  // 召唤师的羁绊
  bool isSummonerSupport = false;
  // 优势属性
  String? advantage;
  // 劣势属性
  String? disadvantage;
  // 开花属性
  final ascendedAsset = Rx<String?>(null);
  // 神龙之花
  int dragonFlower = 0;
  // 突破次数
  int merged = 0;
  // 稀有度
  int rarity = 5;
  // 目标等级
  int targetLevel = 40;

  int oldLevel = 1;

  String get heroName => hero.idTag!.split("_")[1];

  Map<String, int> get growthMap => Map<String, int>.fromIterables(
      statsMap.values, hero.growthRates!.toJson().values);

// 计算得出的最终属性
  // Stats equipStats = Stats(hp: 0, atk: 0, spd: 0, def: 0, res: 0);
  Stats get equipStats {
    return Stats(
        hp: baseStats.hp + skillsStats.hp,
        atk: baseStats.atk + skillsStats.atk,
        spd: baseStats.spd + skillsStats.spd,
        def: baseStats.def + skillsStats.def,
        res: baseStats.res + skillsStats.res);
  }

  bool get hasLegendEffect {
    if (hero.legendary != null) {
      if (hero.legendary!.kind == 1) {
        return true;
      }
    }
    return false;
  }

  List<List<num>> rarityArenaScore = const [
    // [星数基本分，等级系数]
    [47, 68 / 39],
    [49, 73 / 39],
    [51, 79 / 39],
    [53, 84 / 39],
    [55, 7 / 3],
  ];

  /// 总SP分数
  int get allSpCost {
    int _allSpCost = 0;
    // 初始化总sp
    for (Skill? skill in heroSkills.getRange(0, 7)) {
      if (skill != null) {
        _allSpCost += skill.spCost!;
      }
    }
    return _allSpCost;
  }

  int get bst {
    Stats stats = Stats.fromJson(Utils.calcStats(
        hero, 1, 40, rarity, advantage, disadvantage, merged > 0 ? 1 : 0));

    // 从传承效果、A技能、和白值中计算最高的一个值，突破大于0时白值+3
    // 计算0破性格时已经计算过性格对白值的影响(一般会+-3，优劣性格会+-4，因此总白值相对中性
    // 已经有了-1到+1的补充)，这里不需要计算
    return [
      hero.legendary == null ? 0 : hero.legendary!.bst!,
      heroSkills[3] == null
          ? 0
          // 死斗系技能的timingId等于18
          : heroSkills[3]!.timingId != 18
              ? 0
              // 是否传承或神阶英雄，如果是传承或神阶则使用A技能atk的值（仅限死斗4），
              // 否则使用HP的值
              : hero.legendary?.kind == 1
                  // 死斗3的ATK是0，只有死斗4的ATK > 0
                  ? heroSkills[3]!.skillParams!.atk != 0
                      ? heroSkills[3]!.skillParams!.atk
                      : heroSkills[3]!.skillParams!.hp
                  : heroSkills[3]!.skillParams!.hp,
      // 如果突破数大于0，则数值-2（去掉1破时奖励的不计算bst的2点白值）
      merged > 0 ? stats.sum - 2 : stats.sum
    ].reduce((value, element) => m.max(value, element));
  }

  ///竞技场分数
  int get arenaScore {
// 英雄个体分 =
//星数基本分 + floor(等级系数*等级) + 突破*2 + floor(技能SP/100) + floor(白值/5) + 祝福*祝福提供者*4
// 团队分 = (average(英雄个体分1+英雄个体分2+英雄个体分3+英雄个体分4) +150(团队基础分))*2(加分人物奖励)
    return ((rarityArenaScore[rarity - 1][0] as int) +
            ((rarityArenaScore[rarity - 1][1] as double) * targetLevel)
                .floor() +
            merged * 2 +
            (allSpCost / 100).floor() +
            (bst / 5).floor() +
            (heroSkills[7] == null ? 0 : 4) +
            150) *
        2;
  }

  // 突破、性格、神龙之花按钮的key
  GlobalKey<CircleBtnState> mergeBtnKey = GlobalKey<CircleBtnState>();
  GlobalKey<CircleBtnState> dragonBtnKey = GlobalKey<CircleBtnState>();
  GlobalKey<TraitsBtnState> traitsBtnKey = GlobalKey<TraitsBtnState>();

  // 当前所有技能的属性
  Stats skillsStats = Stats(hp: 0, atk: 0, spd: 0, def: 0, res: 0);

  // 未装备技能的属性
  Stats baseStats = Stats(hp: 0, atk: 0, spd: 0, def: 0, res: 0);

  // 属性字典，主要用于性格bottomsheet进行文字和序号的转换
  Map<String, String> statsMap = const {
    "1": "hp",
    "2": "atk",
    "3": "spd",
    "4": "def",
    "5": "res",
  };

  /// 比较两个技能上下级关系，如果S1的前置技能有S2则返回S1，否则返回S2，
  Skill? compareSkill(Skill? s1, Skill? s2) {
    if (s1 == null && s2 == null) {
      return null;
    } else if (s1 == null || s2 == null) {
      return s1 ?? s2;
    } else {
      return s1.prerequisites.contains(s2.idTag) ? s1 : s2;
    }
  }

  /// 遍历一到五星技能，返回各技能栏位最高级的技能,0-5是技能，6，7是圣印，祝福，8（专武）
  List<Skill?> getSkills(Skills? skills) {
    List<Skill?> _skills = [
      null,
      null,
      null,
      null,
      null,
      null,
      null,
    ];

    // ?反正没有一星二星了，从三星遍历好像也可以
    if (skills != null) {
      for (List<String?> skillOnRarity in skills.skills) {
        skillOnRarity.asMap().forEach((index, skillTag) {
          if (skillTag != null) {
            Skill newSkill = Skill.fromJson(data.skillBox.read(skillTag));
            if (newSkill.exclusive! && newSkill.category! == 0 && index > 5) {
              // _skills[6] = compareSkill(_skills[6], newSkill);
              _skills[6] = newSkill;
            } else {
              if (_skills[newSkill.category!] != null) {
                // _skills[newSkill.category!] = newSkill;
                _skills[newSkill.category!] =
                    compareSkill(_skills[newSkill.category!], newSkill);
                // print(_skills[newSkill.category!]);
              } else {
                _skills[newSkill.category!] = newSkill;
              }
            }
          }
        });
      }
    }
    Utils.debug(_skills);
    _skills.insertAll(6, [null, null]);
    return _skills;
  }

  ///通过heroIdTag获取person和skill的实例，返回[person hero ,list<skill?> heroSkills]
  ///[heroSkills]是按weapon,assist,special,passiveA,B,C,skillAccessory,highLevelWeapon顺序的列表
  void initSkills() {
// heroSkills=
//  [
    //   equipedweapon, 默认装备武器
    //   assist,
    //   special,
    //   passiveA,
    //   passiveB,
    //   passiveC,
    // skillAccessory，圣印
    // 祝福
    //   highLevelWeapon?,专武等高等级武器（专武也可能在第一栏位），
    // ]

    // 这里必须获取一遍原版技能，因为有的人物专武直接在0位上，如果删除后保存
    // 打开后就获取不到专武数据了
    List<Skill?> skills = getSkills(hero.skills);

    // {专武:专武效果}
    List<Map<Skill, Skill>> exclusiveList = [];

    if (skills[0] != null) {
      if (skills[0]!.exclusive!) {
        exclusiveList
            .addAll(Utils.getExclusive(skills[0]!.idTag!, data.skillBox));
      }
    }
    if (skills[8] != null) {
      if (skills[8]!.exclusive!) {
        exclusiveList
            .addAll(Utils.getExclusive(skills[8]!.idTag!, data.skillBox));
      }
    }

    if (build.custom) {
      for (var element in build.equipSkills) {
        element != null
            ? origHeroSkills.add(Skill.fromJson(data.skillBox.read(element)))
            : origHeroSkills.add(null);
      }
    } else {
      origHeroSkills = skills;
    }

    origWeaponRefine = exclusiveList;
  }

  ///设置是否神装
  void setResplendent(bool newVal) {
    newVal
        ? baseStats.add(Stats(hp: 2, atk: 2, spd: 2, def: 2, res: 2))
        : baseStats.add(Stats(hp: -2, atk: -2, spd: -2, def: -2, res: -2));
    isResplendent = newVal;
    update();
  }

  ///设置是否召唤师的羁绊
  void setSummmonerSupport(bool newVal) {
    newVal
        ? baseStats.add(Stats(hp: 5, atk: 2, spd: 2, def: 2, res: 2))
        : baseStats.add(Stats(hp: -5, atk: -2, spd: -2, def: -2, res: -2));
    isSummonerSupport = newVal;
    update();
  }

  void delSkill(Skill skill) {
    int index = heroSkills.indexOf(skill);

    skillsStats.add(skill.stats, minus: true);
    skillsStats.atk -= skill.might!;
    if (skill.refineId != null) {
      Skill _ = Skill.fromJson(data.skillBox.read(skill.refineId!));
      skillsStats.add(_.stats, minus: true);
    }
    heroSkills[index] = null;

    update();
  }

  void setSkill(int index, Skill? skill) {
    heroSkills[index] = skill;
    if (skill != null) {
      skillsStats.add(skill.stats);
      skillsStats.atk += skill.might!;
      if (skill.refineId != null) {
        Skill _ = Skill.fromJson(data.skillBox.read(skill.refineId!));
        skillsStats.add(_.stats);
      }
    }
    equipStats.add(skillsStats);
    update();
  }

  void calBaseStats() {
    baseStats = Stats.fromJson(Utils.calcStats(
      hero,
      oldLevel,
      targetLevel,
      rarity,
      advantage,
      disadvantage,
      merged,
      dragonFlower,
      isResplendent,
      isSummonerSupport,
      ascendedAsset.value,
    ));
    equipStats.clear();
    equipStats.add(baseStats);

    equipStats.add(skillsStats);
    update();
  }

  Future click(BuildContext context, String action) async {
    switch (action) {
      case "save":
        save();
        break;
      case "share":
        await showShare(context);
        break;
      case "upload":
        await upload(context);
        break;
      case "web":
        toWeb(context);
        break;
      default:
        break;
    }
  }

  void save() {
    if (build.custom) {
      PersonBuild? newBuild = addToFavorite(build.timeStamp);
      if (newBuild != null) {
        Get.back(result: newBuild);
      }
    } else {
      if (addToFavorite() != null) {
        // 收藏页面没有用obx进行响应式处理，所以这里要手动刷新
        Get.find<FavoritePageController>().refreshData();
        Utils.showToast("成功");
      }
    }
  }

  void toWeb(BuildContext context) {
    if (Get.find<DataService>().allowGetId) {
      Navigator.of(context).pushNamed("/heroBuildShare", arguments: hero);
    } else {
      Utils.showToast("请先到“其他”页面打开信息服务开关");
    }
  }

  Future upload(BuildContext context) async {
    if (!Get.find<DataService>().allowGetId) {
      Utils.showToast("请先到“其他”页面打开信息服务开关");
      return;
    }
    await Cloud().login();
    if (!data.cacheRefreshed) {
      await data.refreshCache();
    }

    List<String>? tags = await showDialog(
        context: context,
        builder: (context) {
          GlobalKey<TagChooseState> s = GlobalKey();
          return SimpleDialog(
            title: const Text("添加标签"),
            children: [
              TagChoose(key: s, data: data.cloudTags),
              const Divider(
                height: 10,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                      onPressed: () {
                        Navigator.of(context).pop(s.currentState!.selected);
                      },
                      child: const Text("确定")),
                  TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text("取消")),
                ],
              )
            ],
          );
        });
    if (tags == null) {
      return;
    }

    PersonBuild _ = PersonBuild(
        personTag: hero.idTag!,
        equipSkills: [for (Skill? skill in heroSkills) skill?.idTag])
      ..merged = merged
      ..advantage = advantage
      ..disAdvantage = disadvantage
      ..rarity = rarity
      ..dragonflowers = dragonFlower
      ..summonerSupport = isSummonerSupport
      ..arenaScore = arenaScore
      ..custom = true
      ..ascendedAsset = ascendedAsset.value
      ..timeStamp = DateTime.now().millisecondsSinceEpoch
      ..resplendent = isResplendent;

    await HeroBuildTable(
      idTag: hero.idTag,
      tags: BArray(op: BArrayMethod.addUnique, objects: tags),
      creator: Cloud().currentUser.username,
      build: Utils.encodeBuild(_, heroSkills.sublist(0, 8), hero),
    ).create();

    Utils.showToast("成功");
  }

  ///添加进收藏 [timeStamp] 是毫秒时间戳，为0代表新增，否则会检索指定的数据修改
  PersonBuild? addToFavorite([int timeStamp = 0]) {
    try {
      PersonBuild _ = PersonBuild(
          personTag: hero.idTag!,
          equipSkills: [for (Skill? skill in heroSkills) skill?.idTag])
        ..merged = merged
        ..advantage = advantage
        ..disAdvantage = disadvantage
        ..rarity = rarity
        ..dragonflowers = dragonFlower
        ..summonerSupport = isSummonerSupport
        ..arenaScore = arenaScore
        ..custom = true
        ..ascendedAsset = ascendedAsset.value
        ..timeStamp = DateTime.now().millisecondsSinceEpoch
        ..resplendent = isResplendent;

      Iterable<Map<String, dynamic>>? values =
          (data.customBox.read("favorites") as Iterable<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
      List<Map<String, dynamic>> favorites = values.toList();
      if (timeStamp != 0) {
        favorites[favorites.indexWhere(
            (element) => element["time_stamp"] == timeStamp)] = _.toJson();
      } else {
        favorites.add(_.toJson());
      }

      data.customBox.write("favorites", favorites);

      return _;
    } catch (e) {
      return null;
    }
  }

  PersonBuild get currentBuild {
    return PersonBuild(
        personTag: hero.idTag!,
        equipSkills: [for (Skill? skill in heroSkills) skill?.idTag])
      ..merged = merged
      ..advantage = advantage
      ..disAdvantage = disadvantage
      ..rarity = rarity
      ..dragonflowers = dragonFlower
      ..summonerSupport = isSummonerSupport
      ..arenaScore = arenaScore
      ..ascendedAsset = ascendedAsset.value
      ..resplendent = isResplendent;
  }

  Future<void> showShare(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ShareWidget(
          build: currentBuild,
          equipedStats: equipStats,
        ),
      ),
    );
  }

  HeroDetailController();

  @override
  void onInit() {
    hero = Person.fromJson(data.personBox.read(build.personTag));

    if (build.custom) {
      advantage = build.advantage;
      disadvantage = build.disAdvantage;
      rarity = build.rarity;
      merged = build.merged;
      dragonFlower = build.dragonflowers;
      isResplendent = build.resplendent;
      isSummonerSupport = build.summonerSupport;
      ascendedAsset.value = build.ascendedAsset;
    } else {}

    initSkills();
    heroSkills = [...origHeroSkills];

    baseStats = build.custom
        ? Stats.fromJson(Utils.calcStats(
            hero,
            1,
            40,
            rarity,
            advantage,
            disadvantage,
            merged,
            dragonFlower,
            isResplendent,
            isSummonerSupport,
            ascendedAsset.value,
          ))
        : Stats.fromJson(Utils.calcStats(hero, 1, 40, 5));

    if (heroSkills.isNotEmpty) {
      // 技能栏有6+2 圣印，祝福，+1（专武），这里只取前8个
      for (Skill? s in heroSkills.getRange(0, 8)) {
        if (s != null) {
          skillsStats.atk += s.might!;
          skillsStats.add(s.stats);
          if (s.refineId != null && s.category == 0) {
            Skill _s = Skill.fromJson(data.skillBox.read(s.refineId!));
            skillsStats.add(_s.stats);
          }
          // tempStats.add(skillStats);
        }
      }
    }

    equipStats.add(baseStats);
    equipStats.add(skillsStats);

    super.onInit();
  }
}
