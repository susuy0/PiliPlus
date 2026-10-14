import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class FeedCacheTrack {
  const FeedCacheTrack({required this.url, required this.indexEnd});
  final String url;
  final int indexEnd;

  static FeedCacheTrack? fromSegmentBase(String url, Map? base) {
    final range =
        base?['indexRange'] ?? base?['index_range'] ?? base?['IndexRange'];
    final parts = range?.toString().split('-');
    if (parts?.length != 2) return null;
    final end = int.tryParse(parts![1]);
    if (end == null || end < 0 || end >= 256 * 1024) return null;
    return FeedCacheTrack(url: url, indexEnd: end);
  }
}

class FeedPrefixPlan {
  const FeedPrefixPlan(this.end, this.duration);
  final int end;
  final Duration duration;

  /// ISO BMFF sidx: include complete initial media fragments covering >=3s.
  static FeedPrefixPlan parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var box = 0;
    while (box + 8 <= bytes.length) {
      var size = data.getUint32(box);
      final type = String.fromCharCodes(bytes.sublist(box + 4, box + 8));
      var header = 8;
      if (size == 1) {
        if (box + 16 > bytes.length) break;
        size = data.getUint64(box + 8);
        header = 16;
      }
      if (size < header || box + size > bytes.length) break;
      if (type == 'sidx') {
        var p = box + header;
        if (p + 12 > box + size) break;
        final version = data.getUint8(p);
        if (version > 1) throw const FormatException('unsupported sidx');
        final timescale = data.getUint32(p + 8);
        p += 12;
        final timeSize = version == 0 ? 4 : 8;
        if (p + timeSize * 2 + 4 > box + size || timescale == 0) break;
        p += timeSize; // earliest presentation time
        final firstOffset = version == 0
            ? data.getUint32(p)
            : data.getUint64(p);
        p += timeSize;
        final count = data.getUint16(p + 2);
        p += 4;
        if (p + count * 12 > box + size || count == 0) break;
        var end = box + size + firstOffset - 1;
        var ticks = 0;
        for (var i = 0; i < count; i++, p += 12) {
          final reference = data.getUint32(p);
          final length = reference & 0x7fffffff;
          final duration = data.getUint32(p + 4);
          if (reference >> 31 != 0 || length == 0 || duration == 0) {
            throw const FormatException('invalid media reference');
          }
          end += length;
          ticks += duration;
          if (ticks >= timescale * 3 || i == count - 1) {
            return FeedPrefixPlan(
              end,
              Duration(microseconds: ticks * 1000000 ~/ timescale),
            );
          }
        }
      }
      box += size;
    }
    throw const FormatException('missing complete sidx');
  }
}

class _Prefix {
  _Prefix(this.url, this.bytes, this.total, this.duration, this.footer);
  final String url;
  final Uint8List bytes;
  final int total;
  final Duration duration;
  final Uint8List footer;
  int get footerStart => total - footer.length;
}

class FeedCachedMedia {
  FeedCachedMedia(this._tracks);
  final List<_Prefix> _tracks;
  int get byteCount =>
      _tracks.fold(0, (n, t) => n + t.bytes.length + t.footer.length);
  Duration get duration =>
      _tracks.map((t) => t.duration).reduce((a, b) => a < b ? a : b);
}

/// One active prefix and one next prefix. No decoder or second player exists.
/// All later ranges are streamed to the original foreground player unchanged.
class FeedMediaCache {
  FeedMediaCache({required this.userAgent, required this.referer});
  final String userAgent;
  final String referer;
  static const maxBytes = 32 * 1024 * 1024;
  // A demuxer's initial AVIO read can exceed three seconds of low-bitrate
  // audio/video. Cache enough bytes for that read as well as complete >=3s
  // fragments, otherwise even the first frame waits for the remote tail.
  static const startupBytes = 256 * 1024;
  static const footerBytes = 64 * 1024;
  final _active = <String, _Prefix>{};
  final _warmClients = <HttpClient>{};
  final _streams = <HttpClient>{};
  HttpServer? _server;
  bool _closed = false;
  int _nextId = 0;
  late final _token = List.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();

  Future<FeedCachedMedia> prepare(
    List<FeedCacheTrack> tracks,
    bool Function() current,
  ) async {
    if (_closed || tracks.isEmpty || !current())
      throw StateError('inactive preload');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    _warmClients.add(client);
    final prefixes = <_Prefix>[];
    var used = 0;
    try {
      // Audio first makes the shared byte budget deterministic.
      for (final track in tracks) {
        if (!current() || _closed) throw StateError('cancelled preload');
        final head = await _read(client, track.url, 0, track.indexEnd, current);
        final plan = FeedPrefixPlan.parse(head.bytes);
        final end = min(head.total - 1, max(plan.end, startupBytes - 1));
        final footerStart = max(end + 1, head.total - footerBytes);
        if (plan.end >= head.total ||
            end + 1 + head.total - footerStart > maxBytes - used) {
          throw const FormatException('media prefix outside cache budget');
        }
        final tail = end > track.indexEnd
            ? await _read(
                client,
                track.url,
                track.indexEnd + 1,
                end,
                current,
              )
            : null;
        if (tail != null && tail.total != head.total)
          throw const FormatException('media length changed');
        final bytes = Uint8List(end + 1)
          ..setRange(0, head.bytes.length, head.bytes);
        if (tail != null)
          bytes.setRange(head.bytes.length, bytes.length, tail.bytes);
        // Fragmented MP4 readers may seek to mfra/mfro at EOF before decoding
        // the first cached fragment. Include that probe, without fetching the
        // unplayed middle of the video.
        final footer = footerStart < head.total
            ? await _read(
                client,
                track.url,
                footerStart,
                head.total - 1,
                current,
              )
            : null;
        if (footer != null && footer.total != head.total)
          throw const FormatException('media length changed');
        final footerData = footer?.bytes ?? Uint8List(0);
        prefixes.add(
          _Prefix(track.url, bytes, head.total, plan.duration, footerData),
        );
        used += bytes.length + footerData.length;
      }
      if (!current() || _closed) throw StateError('cancelled preload');
      return FeedCachedMedia(prefixes);
    } finally {
      _warmClients.remove(client);
      client.close(force: true);
    }
  }

  void cancelPending() {
    for (final client in _warmClients) {
      client.close(force: true);
    }
    _warmClients.clear();
  }

  Future<void> release(FeedCachedMedia media) async {
    // Removing the pool reference frees unactivated prefixes; active tracks
    // live until the next original player.open has completed.
  }

  Future<Map<String, String>> activate(FeedCachedMedia media) async {
    if (_closed) throw StateError('cache closed');
    _server ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_closed) {
      await _server!.close(force: true);
      throw StateError('cache closed');
    }
    if (!_listening) {
      _listening = true;
      _server!.listen((request) {
        unawaited(_serve(request));
      });
    }
    final urls = <String, String>{};
    for (final track in media._tracks) {
      final id = '${_token}_${_nextId++}';
      _active[id] = track;
      urls[track.url] = 'http://127.0.0.1:${_server!.port}/$id';
    }
    return urls;
  }

  bool _listening = false;

  bool owns(String uri) =>
      _server != null &&
      uri.contains('http://127.0.0.1:${_server!.port}/$_token');

  void retain(Set<String> urls) {
    final ids = urls.map((url) => Uri.parse(url).path.substring(1)).toSet();
    _active.removeWhere((id, _) => !ids.contains(id));
  }

  Future<({Uint8List bytes, int total})> _read(
    HttpClient client,
    String url,
    int start,
    int end,
    bool Function() current,
  ) async {
    final request = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 5));
    _headers(request, start, end);
    final response = await request.close().timeout(const Duration(seconds: 5));
    final total = _validate(response, start, end);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 5))) {
      if (!current() || _closed) {
        request.abort();
        throw StateError('cancelled preload');
      }
      builder.add(chunk);
      if (builder.length > end - start + 1) {
        request.abort();
        throw const FormatException('oversized range');
      }
    }
    if (builder.length != end - start + 1)
      throw const FormatException('truncated range');
    return (bytes: builder.takeBytes(), total: total);
  }

  void _headers(HttpClientRequest request, int start, int end) {
    request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    request.headers.set(HttpHeaders.refererHeader, referer);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  }

  int _validate(HttpClientResponse response, int start, int end) {
    final match = RegExp(
      r'^bytes (\d+)-(\d+)/(\d+)$',
    ).firstMatch(response.headers.value(HttpHeaders.contentRangeHeader) ?? '');
    if (response.statusCode != HttpStatus.partialContent ||
        match == null ||
        int.parse(match[1]!) != start ||
        int.parse(match[2]!) != end) {
      throw const FormatException('CDN did not honor media range');
    }
    final total = int.parse(match[3]!);
    final encoding = response.headers.value(HttpHeaders.contentEncodingHeader);
    if (total <= end || (encoding != null && encoding != 'identity')) {
      throw const FormatException('invalid media range');
    }
    return total;
  }

  Future<void> _serve(HttpRequest incoming) async {
    final out = incoming.response;
    HttpClient? client;
    HttpClientRequest? upstream;
    try {
      final id = incoming.uri.path.substring(1);
      final track = _active[id];
      if (track == null || !{'GET', 'HEAD'}.contains(incoming.method)) {
        out.statusCode = HttpStatus.notFound;
        await out.close();
        return;
      }
      final range = incoming.headers.value(HttpHeaders.rangeHeader);
      var start = 0;
      var end = track.total - 1;
      if (range != null) {
        final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
        if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty))
          throw const FormatException('invalid range');
        if (match[1]!.isEmpty) {
          final suffix = int.parse(match[2]!);
          if (suffix <= 0) throw const FormatException('invalid suffix');
          start = max(0, track.total - suffix);
        } else {
          start = int.parse(match[1]!);
          if (match[2]!.isNotEmpty) end = min(end, int.parse(match[2]!));
        }
        if (start > end || start >= track.total)
          throw const FormatException('range outside media');
        out.statusCode = HttpStatus.partialContent;
        out.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${track.total}',
        );
      }
      out.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      out.bufferOutput = false;
      out.headers.contentType = ContentType('video', 'mp4');
      out.contentLength = end - start + 1;
      if (incoming.method == 'HEAD') {
        await out.close();
        return;
      }
      final cachedEnd = min(end + 1, track.bytes.length);
      if (start < cachedEnd) {
        out.add(Uint8List.sublistView(track.bytes, start, cachedEnd));
        await out.flush();
      }
      final remoteStart = max(start, track.bytes.length);
      final remoteEnd = min(end, track.footerStart - 1);
      if (remoteStart <= remoteEnd) {
        client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
        _streams.add(client);
        unawaited(
          out.done.then<void>(
            (_) {
              upstream?.abort();
              client?.close(force: true);
            },
            onError: (Object _) {
              upstream?.abort();
              client?.close(force: true);
            },
          ),
        );
        upstream = await client
            .getUrl(Uri.parse(track.url))
            .timeout(const Duration(seconds: 5));
        _headers(upstream, remoteStart, remoteEnd);
        final response = await upstream.close().timeout(
          const Duration(seconds: 5),
        );
        if (_validate(response, remoteStart, remoteEnd) != track.total)
          throw const FormatException('media changed');
        await out.addStream(response.timeout(const Duration(seconds: 10)));
      }
      final footerStart = max(start, track.footerStart);
      if (footerStart <= end) {
        out.add(
          Uint8List.sublistView(
            track.footer,
            footerStart - track.footerStart,
            end + 1 - track.footerStart,
          ),
        );
      }
      await out.close();
    } on FormatException {
      try {
        out.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        out.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes */${_active[incoming.uri.path.substring(1)]?.total ?? 0}',
        );
        await out.close();
      } catch (_) {
        await out.close().catchError((Object _) {});
      }
    } catch (_) {
      try {
        out.statusCode = HttpStatus.badGateway;
        await out.close();
      } catch (_) {
        await out.close().catchError((Object _) {});
      }
    } finally {
      upstream?.abort();
      if (client != null) {
        _streams.remove(client);
        client.close(force: true);
      }
    }
  }

  Future<void> dispose() async {
    _closed = true;
    cancelPending();
    for (final client in _streams) {
      client.close(force: true);
    }
    _streams.clear();
    _active.clear();
    await _server?.close(force: true);
  }
}
