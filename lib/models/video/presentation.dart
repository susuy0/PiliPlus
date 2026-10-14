import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';

/// API video geometry, independent of cover proportions or Story membership.
abstract final class VideoPresentation {
  static Dimension? dimension(Map json, {String? uri}) {
    int? number(dynamic value) => value is int ? value : int.tryParse('$value');
    final args = json['player_args'];
    final raw = json['dimension'] ?? (args is Map ? args['dimension'] : null);
    if (raw is Map) {
      final value = Dimension.fromJson({
        'width': number(raw['width']),
        'height': number(raw['height']),
        'rotate': number(raw['rotate']),
      });
      if (valid(value)) return value;
    }
    Map<String, String> params = {};
    try {
      params = Uri.parse(uri ?? json['uri'] ?? '').queryParameters;
    } catch (_) {}
    final w = number(
      (args is Map ? args['width'] : null) ?? params['player_width'],
    );
    final h = number(
      (args is Map ? args['height'] : null) ?? params['player_height'],
    );
    final rotate = number(
      (args is Map ? args['rotate'] : null) ?? params['player_rotate'],
    );
    final value = Dimension(
      width: rotate == 1 ? h : w,
      height: rotate == 1 ? w : h,
    );
    return valid(value) ? value : null;
  }

  static bool valid(Dimension? value) =>
      (value?.width ?? 0) > 0 && (value?.height ?? 0) > 0;
  static List<String> labels(Map json) {
    final labels = <String>{};
    if (json['rights'] is Map && json['rights']['is_stein_gate'] == 1)
      labels.add('互动视频');
    final exclusive = json['is_upower_exclusive'];
    if (exclusive == true || exclusive == 1) labels.add('充电专属');
    void add(dynamic value) {
      if (value is String &&
          value.length <= 60 &&
          (value.contains('充电') ||
              value.contains('专属') ||
              value.contains('AI生成'))) {
        labels.add(value);
      } else if (value is Map) {
        add(value['text'] ?? value['content'] ?? value['title']);
      } else if (value is List) {
        for (final item in value) {
          add(item);
        }
      }
    }

    for (final key in [
      'badge',
      'badges',
      'badge_info',
      'rcmd_reason',
      'upower_exclusive',
    ]) {
      add(json[key]);
    }
    return labels.take(3).toList(growable: false);
  }
}
