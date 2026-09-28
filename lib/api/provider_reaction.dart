import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What this device has done with one provider card: saved it, liked it, or
/// marked it not interested. Bookmark is independent of the other two; **like
/// and dislike are mutually exclusive** — the transitions below are the one
/// place that rule lives, so the UI and the store can't disagree about it.
@immutable
class ProviderReaction {
  const ProviderReaction({this.saved = false, this.liked = false, this.disliked = false});

  static const none = ProviderReaction();

  final bool saved;
  final bool liked;
  final bool disliked;

  ProviderReaction toggleSaved() => ProviderReaction(saved: !saved, liked: liked, disliked: disliked);

  /// Liking clears a dislike; tapping an already-liked card un-likes it.
  ProviderReaction toggleLiked() =>
      ProviderReaction(saved: saved, liked: !liked, disliked: false);

  /// Disliking clears a like; tapping an already-disliked card undoes it.
  ProviderReaction toggleDisliked() =>
      ProviderReaction(saved: saved, liked: false, disliked: !disliked);

  @override
  bool operator ==(Object other) =>
      other is ProviderReaction && other.saved == saved && other.liked == liked && other.disliked == disliked;

  @override
  int get hashCode => Object.hash(saved, liked, disliked);

  @override
  String toString() => 'ProviderReaction(saved: $saved, liked: $liked, disliked: $disliked)';
}

/// Persists [ProviderReaction]s on this device, keyed by the provider's place
/// id (the id that stays stable across searches and sessions).
///
/// Device-local on purpose: like every other per-customer thing in this app
/// (the device id, "Your requests"), a customer is identified by their device,
/// not an account — so reactions survive restarts but don't follow a person to
/// another phone. Nothing is sent to the backend.
///
/// Stored as three string lists (saved / liked / disliked place ids) in
/// SharedPreferences. A provider with no place id (never happens for real
/// search results) can't be keyed, so its reaction just isn't persisted.
class ProviderReactionStore {
  static const _savedKey = 'provider_reactions_saved';
  static const _likedKey = 'provider_reactions_liked';
  static const _dislikedKey = 'provider_reactions_disliked';

  static Future<ProviderReaction> load(String? placeId) async {
    if (placeId == null || placeId.isEmpty) return ProviderReaction.none;
    try {
      final prefs = await SharedPreferences.getInstance();
      final liked = (prefs.getStringList(_likedKey) ?? const []).contains(placeId);
      return ProviderReaction(
        saved: (prefs.getStringList(_savedKey) ?? const []).contains(placeId),
        liked: liked,
        // Like and dislike can't both be set; if damaged storage says both,
        // like wins and the next save repairs it.
        disliked: !liked && (prefs.getStringList(_dislikedKey) ?? const []).contains(placeId),
      );
    } catch (e) {
      debugPrint('ProviderReactionStore: could not read reactions (${e.runtimeType})');
      return ProviderReaction.none;
    }
  }

  /// Best-effort: a failed write is logged and dropped rather than thrown —
  /// the card already shows the new state, and losing persistence for one tap
  /// shouldn't break it.
  static Future<void> save(String? placeId, ProviderReaction reaction) async {
    if (placeId == null || placeId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Each list is read, changed and written back in one synchronous
      // stretch, so two cards saving at once can't overwrite each other.
      await _setMembership(prefs, _savedKey, placeId, reaction.saved);
      await _setMembership(prefs, _likedKey, placeId, reaction.liked);
      await _setMembership(prefs, _dislikedKey, placeId, reaction.disliked && !reaction.liked);
    } catch (e) {
      debugPrint('ProviderReactionStore: could not save reactions (${e.runtimeType})');
    }
  }

  static Future<void> _setMembership(SharedPreferences prefs, String key, String placeId, bool member) {
    final ids = {...(prefs.getStringList(key) ?? const <String>[])};
    member ? ids.add(placeId) : ids.remove(placeId);
    return prefs.setStringList(key, ids.toList());
  }
}
