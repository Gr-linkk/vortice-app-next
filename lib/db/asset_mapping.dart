import 'package:drift/drift.dart' show Value;
import 'package:vortice_app/db/database.dart';
import 'package:vortice_app/models/asset.dart';

AssetsTableCompanion assetToCompanion(Asset asset) => AssetsTableCompanion(
  id: Value(asset.id),
  clientId: Value(asset.clientId),
  assetTypeId: Value(asset.assetTypeId),
  name: Value(asset.name),
  make: Value(asset.make),
  model: Value(asset.model),
  year: Value(asset.year),
  serialNumber: Value(asset.serialNumber),
  location: Value(asset.location),
  notes: Value(asset.notes),
  telemetryEnabled: Value(asset.telemetryEnabled),
  telemetrySource: Value(asset.telemetrySource),
  createdAt: Value(asset.createdAt),
  updatedAt: Value(asset.updatedAt),
);
