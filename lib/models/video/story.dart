import 'package:PiliPlus/models/video/presentation.dart';
import 'package:PiliPlus/models/model_owner.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models/model_video.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart';
import 'package:PiliPlus/utils/id_utils.dart';

/// A playable archive from the official Story feed (not a live/ad card).
class StoryVideoItem extends BaseRcmdVideoItemModel {
  StoryVideoItem({
    required int aid,
    required String bvid,
    int? cid,
    String? title,
    String? cover,
  }) {
    this.aid = aid;
    this.bvid = bvid;
    this.cid = cid;
    this.title = title ?? '';
    this.cover = cover;
    goto = 'av';
    owner = Owner();
    stat = StoryStat.fromJson({});
  }

  int? followers;
  String? searchKeyword, searchTitle, argueMessage;

  StoryStat? get storyStat => stat is StoryStat ? stat as StoryStat : null;

  BaseEpisodeItem get episode => BaseEpisodeItem(
    aid: aid,
    bvid: bvid,
    cid: cid,
    title: title,
    cover: cover,
  );

  static int? _int(dynamic value) => switch (value) {
    int value => value,
    String value => int.tryParse(value),
    _ => null,
  };

  static StoryVideoItem? tryParse(Map<String, dynamic> json) {
    final kind = json['card_goto'] ?? json['goto'];
    if ((kind != 'vertical_av' && kind != 'av') ||
        json['ad_info'] != null ||
        json['can_play'] == 0) {
      return null;
    }
    final playerArgs = json['player_args'] as Map?;
    final aid = _int(playerArgs?['aid'] ?? json['aid'] ?? json['param']);
    if (aid == null || aid <= 0) return null;
    final item =
        StoryVideoItem(
            aid: aid,
            bvid: json['bvid'] as String? ?? IdUtils.av2bv(aid),
            cid: _int(playerArgs?['cid'] ?? json['cid']),
            title: json['title'] as String?,
            cover: json['cover'] as String? ?? json['pic'] as String?,
          )
          ..followers = _int(
            json['owner']?['fans'] ?? json['owner']?['follower'],
          )
          ..verticalHint = kind == 'vertical_av'
          ..contentLabels = VideoPresentation.labels(json)
          ..uri = json['uri'] as String?
          ..duration = _int(json['duration']) ?? 0
          ..owner = json['owner'] is Map
              ? Owner.fromJson(Map<String, dynamic>.from(json['owner'] as Map))
              : Owner()
          ..stat = json['stat'] is Map
              ? StoryStat.fromJson(
                  Map<String, dynamic>.from(json['stat'] as Map),
                )
              : StoryStat.fromJson({})
          ..isFollowed =
              json['req_user']?['attention'] == 1 ||
              json['owner']?['relation']?['status'] == 2;
    final entrance = json['creative_entrance'];
    if (entrance is Map && entrance['type'] == 6) {
      try {
        final keyword = Uri.parse(entrance['jump_uri']?.toString() ?? '')
            .queryParameters['keyword'];
        if (keyword != null && keyword.trim().isNotEmpty) {
          item.searchKeyword = keyword;
          item.searchTitle = entrance['title']?.toString();
        }
      } on FormatException {
        /* Invalid cards have no search entry. */
      }
    }
    item.argueMessage = json['argue_msg'] as String?;
    if (json['dimension'] is Map) {
      item.dimension = Dimension.fromJson(
        Map<String, dynamic>.from(json['dimension'] as Map),
      );
    }
    try {
      final params = Uri.parse(item.uri ?? '').queryParameters;
      item.cid ??= _int(params['cid']);
      item.dimension ??= Dimension.fromJson({
        'width': _int(params['player_width']),
        'height': _int(params['player_height']),
        'rotate': _int(params['player_rotate']),
      });
    } on FormatException {
      // Missing cid is resolved through pagelist when this item is played.
    }
    return item;
  }
}

/// Preserve Story API interaction counts for pages sliding in before the
/// detailed archive request completes. Unknown counts remain unknown.
class StoryStat extends Stat {
  StoryStat.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    reply = StoryVideoItem._int(json['reply']);
    coin = StoryVideoItem._int(json['coin']);
    favorite = StoryVideoItem._int(json['favorite']);
    share = StoryVideoItem._int(json['share']);
  }
  int? reply, coin, favorite, share;
}
