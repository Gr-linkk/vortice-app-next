/// Stable vocabulary for local offline and sync state.
///
/// These values are persisted in Drift tables and should remain backwards
/// compatible once data exists on devices.
enum SyncStatus {
  synced(SyncStatusValues.synced),
  pendingCreate(SyncStatusValues.pendingCreate),
  pendingUpdate(SyncStatusValues.pendingUpdate),
  pendingDelete(SyncStatusValues.pendingDelete),
  syncing(SyncStatusValues.syncing),
  failed(SyncStatusValues.failed),
  conflict(SyncStatusValues.conflict);

  const SyncStatus(this.dbValue);

  final String dbValue;

  static SyncStatus fromDbValue(String value) => SyncStatus.values.firstWhere(
        (status) => status.dbValue == value,
        orElse: () => SyncStatus.failed,
      );
}

abstract final class SyncStatusValues {
  static const synced = 'synced';
  static const pendingCreate = 'pending_create';
  static const pendingUpdate = 'pending_update';
  static const pendingDelete = 'pending_delete';
  static const syncing = 'syncing';
  static const failed = 'failed';
  static const conflict = 'conflict';
}

/// Stable vocabulary for queued offline sync work.
enum SyncOperationType {
  create(SyncOperationTypeValues.create),
  update(SyncOperationTypeValues.update),
  delete(SyncOperationTypeValues.delete),
  uploadFile(SyncOperationTypeValues.uploadFile),
  attachFile(SyncOperationTypeValues.attachFile);

  const SyncOperationType(this.dbValue);

  final String dbValue;

  static SyncOperationType fromDbValue(String value) =>
      SyncOperationType.values.firstWhere(
        (type) => type.dbValue == value,
        orElse: () => SyncOperationType.update,
      );
}

abstract final class SyncOperationTypeValues {
  static const create = 'create';
  static const update = 'update';
  static const delete = 'delete';
  static const uploadFile = 'upload_file';
  static const attachFile = 'attach_file';
}

/// Stable vocabulary for locally staged file attachments.
enum LocalAttachmentPurpose {
  checklistPhoto(LocalAttachmentPurposeValues.checklistPhoto),
  serviceReportPhoto(LocalAttachmentPurposeValues.serviceReportPhoto),
  techSignature(LocalAttachmentPurposeValues.techSignature),
  other(LocalAttachmentPurposeValues.other);

  const LocalAttachmentPurpose(this.dbValue);

  final String dbValue;

  static LocalAttachmentPurpose fromDbValue(String value) =>
      LocalAttachmentPurpose.values.firstWhere(
        (purpose) => purpose.dbValue == value,
        orElse: () => LocalAttachmentPurpose.other,
      );
}

abstract final class LocalAttachmentPurposeValues {
  static const checklistPhoto = 'checklist_photo';
  static const serviceReportPhoto = 'service_report_photo';
  static const techSignature = 'tech_signature';
  static const other = 'other';
}
