import 'package:PiliPlus/models/video/story.dart';
import 'package:PiliPlus/models/video/presentation.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/utils/id_utils.dart';

/// Keep the original season's section/episode order and current archive.
/// Entries use the same episode metadata as the original collection panel.
({List<StoryVideoItem> items, int index})? collectionFeed(
  VideoDetailData detail,
  StoryVideoItem current,
) {
  final items = <StoryVideoItem>[];
  final seen = <int>{};
  for (final section in detail.ugcSeason?.sections ?? []) {
    for (final episode in section.episodes ?? []) {
      var aid = episode.aid ?? episode.arc?.aid;
      if (aid == null && episode.bvid?.isNotEmpty == true) {
        try {
          aid = IdUtils.bv2av(episode.bvid!);
        } catch (_) {
          continue;
        }
      }
      if (aid == null || aid <= 0 || !seen.add(aid)) continue;
      if (aid == current.aid) {
        items.add(current);
        continue;
      }
      final arc = episode.arc;
      final stat = arc?.stat;
      items.add(
        StoryVideoItem(
            aid: aid,
            bvid: episode.bvid?.isNotEmpty == true
                ? episode.bvid!
                : IdUtils.av2bv(aid),
            cid: episode.cid ?? episode.page?.cid,
            title: episode.title ?? arc?.title,
            cover: arc?.pic,
          )
          ..owner = arc?.author ?? detail.owner ?? current.owner
          ..duration = arc?.duration ?? episode.page?.duration ?? 0
          ..dimension = arc?.dimension ?? episode.page?.dimension
          ..contentLabels = VideoPresentation.labels({'badge': episode.badge})
          ..stat = StoryStat.fromJson({
            'view': stat?.view,
            'like': stat?.like,
            'reply': stat?.reply,
            'coin': stat?.coin.toInt(),
            'favorite': stat?.favorite,
            'share': stat?.share,
          }),
      );
    }
  }
  final index = items.indexWhere((item) => item.aid == current.aid);
  if (index < 0) return null;
  return (items: items, index: index);
}
