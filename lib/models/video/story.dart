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
    stat = Stat.fromJson({});
  }

  Dimension? dimension;

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
          ..uri = json['uri'] as String?
          ..duration = _int(json['duration']) ?? 0
          ..owner = json['owner'] is Map
              ? Owner.fromJson(Map<String, dynamic>.from(json['owner'] as Map))
              : Owner()
          ..stat = json['stat'] is Map
              ? Stat.fromJson(Map<String, dynamic>.from(json['stat'] as Map))
              : Stat.fromJson({})
          ..isFollowed =
              json['req_user']?['attention'] == 1 ||
              json['owner']?['relation']?['status'] == 2;
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
