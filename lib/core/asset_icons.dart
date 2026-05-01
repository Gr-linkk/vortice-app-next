import 'package:flutter/material.dart';

/// Returns an [IconData] appropriate for the given [assetTypeId].
///
/// Matching is done on the last 3 hex characters of the UUID:
///   001–006  → [Icons.directions_boat]
///   007–008  → [Icons.water]
///   009, 00a, 00b → [Icons.construction]
///   00c      → [Icons.bolt]
///   00d or any other → [Icons.category]
IconData assetIconFor(String assetTypeId) {
  final lower = assetTypeId.toLowerCase();
  // Take the last 3 characters of the UUID string
  final suffix = lower.length >= 3 ? lower.substring(lower.length - 3) : lower;

  const boatSuffixes = {'001', '002', '003', '004', '005', '006'};
  if (boatSuffixes.contains(suffix)) return Icons.directions_boat;

  if (suffix == '007' || suffix == '008') return Icons.water;

  if (suffix == '009' || suffix == '00a' || suffix == '00b') {
    return Icons.construction;
  }

  if (suffix == '00c') return Icons.bolt;

  // '00d' and all unrecognised suffixes
  return Icons.category;
}
