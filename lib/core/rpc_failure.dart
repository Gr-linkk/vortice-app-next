import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Whether a write received a known database rejection rather than an
/// uncertain delivery/response failure. Only a confirmed rejection permits
/// replacing the saved operation identity or editing its frozen payload.
///
/// PostgrestException also represents gateway and protocol failures. Even a
/// five-character SQLSTATE is insufficient: 08007 and 40003 explicitly mean
/// that transaction/statement completion is unknown. Unrecognized failures
/// therefore retain the original operation for exact retry.
/// https://www.postgresql.org/docs/current/errcodes-appendix.html
bool rpcWriteWasRejected(Object error) {
  if (error is! PostgrestException) return false;
  final code = error.code;
  if (code == 'P0001' || code == '40001' || code == '40P01') return true;
  // Invalid input, violated constraints, and access/query errors are known
  // statement rejections. Do not classify arbitrary SQLSTATEs as rollback.
  return code != null && RegExp(r'^(22|23|42)[0-9A-Z]{3}$').hasMatch(code);
}
