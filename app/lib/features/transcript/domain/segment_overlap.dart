import 'dart:math';

/// Recouvrement temporel de deux segments, en « intersection sur union »
/// (cf. cowork/02-architecture.md §5.3). Les quatre horodatages doivent être
/// sur la **même** horloge — celle de l'hôte, après correction par
/// `SyncedClock`.
///
/// Rend 0 quand les segments ne se touchent pas, 1 quand ils coïncident.
/// Deux segments de durée nulle au même instant valent 1 : ils décrivent bien
/// le même moment, même si aucun VAD ne devrait en produire.
double temporalIou({
  required int aStartMs,
  required int aEndMs,
  required int bStartMs,
  required int bEndMs,
}) {
  final intersection = min(aEndMs, bEndMs) - max(aStartMs, bStartMs);
  if (intersection <= 0) {
    return aStartMs == bStartMs && aEndMs == bEndMs ? 1 : 0;
  }
  final union = (aEndMs - aStartMs) + (bEndMs - bStartMs) - intersection;
  if (union <= 0) return 1;
  return intersection / union;
}
