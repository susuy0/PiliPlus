# Playback and Story changes

- Seeks carry media and request generations. A cancelled or superseded request cannot seek a later video; seek callers await native completion.
- Temporary speed commands preserve the pre-hold speed, serialize the release, and ignore stale completions. Pointer cancellation, focus loss, widget disposal and lifecycle changes restore the normal rate.
- SponsorBlock responses and segments belong to the current request generation. Old responses, deferred play listeners and out-of-range segments cannot skip the current video.
- On iOS, the existing texture registry hook counts native frame notifications. Recovery requires four seconds without notifications while the playback clock advances, excludes pause/buffering/background/audio-only/near-EOF states, and is limited to two attempts per media with a thirty-second cooldown. Static scenes still produce frame notifications. This needs real-device verification; a texture notification is not proof of physical screen presentation.
- Story preload has independent network and duration settings. Duration defaults to three seconds, accepts one to thirty seconds, and selects complete DASH fragments. Startup and MP4 footer probes remain cached. Longer prefixes have a bounded byte budget.
- The Shorts tab hands off directly to the normal Story player, with discovery pagination and a saved video/position for subsequent entries.
- Danmaku is clipped to the contained video rectangle. The original player progress and high-energy curve are rendered together in the moving Story footer; the native inline progress duplicate is hidden.

Validation: standalone playback-session and media-cache regressions, plus native UI tests for direct entry, late discovery cancellation, stale skip responses and invalid segment endpoints. iOS/Mac release builds validate native compilation and signing; they do not replace device playback tests.
