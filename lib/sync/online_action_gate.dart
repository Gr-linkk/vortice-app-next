import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vortice_app/core/account_storage.dart';
import 'package:vortice_app/core/supabase_client.dart';
import 'package:vortice_app/core/user_feedback.dart';
import 'package:vortice_app/features/auth/auth_provider.dart';

enum ServerConnection { unknown, online, offline }

/// This is a reachability check, never authorization for the subsequent write.
/// The write still runs its normal current membership and revision checks.
class OnlineActionGate extends StateNotifier<ServerConnection> {
  OnlineActionGate({required this.account,required this.currentAccount,required this.probe,this.now = DateTime.now}) : super(ServerConnection.unknown);
  final String account;
  final String? Function() currentAccount;
  final Future<void> Function() probe;
  final DateTime Function() now;
  DateTime? _checkedAt;
  Future<bool>? _pending;
  bool _closed = false;

  Future<bool> check({bool force = false}) {
    if(_closed || currentAccount() != account) return Future.value(false);
    if(_pending != null) return _pending!;
    // Briefly share a successful check between opening and submitting a dialog.
    if(!force && state == ServerConnection.online && _checkedAt != null && now().difference(_checkedAt!) < const Duration(seconds: 10)) return Future.value(true);
    return _pending = _check().whenComplete(()=>_pending=null);
  }
  Future<bool> _check() async {
    try {
      await probe();
      if(_closed || currentAccount() != account) return false;
      _checkedAt = now();
      state = ServerConnection.online;
      return true;
    } catch(error) {
      if(_closed || currentAccount() != account) return false;
      if(isConnectionFailure(error)) { state = ServerConnection.offline; return false; }
      // A server rejection proves reachability, while the write retains its
      // own authentication error and never receives a local approval.
      if(isAccessDenial(error)) { state = ServerConnection.online; return true; }
      rethrow;
    }
  }
  @override
  void dispose() { _closed=true; super.dispose(); }
}

final onlineActionGateProvider = StateNotifierProvider<OnlineActionGate,ServerConnection>((ref) {
  final account = ref.watch(sessionProvider)?.user.id ?? 'signed_out';
  return OnlineActionGate(account:account,currentAccount:()=>supabase.auth.currentUser?.id,probe:() async {
    await supabase.from('profiles').select('id').eq('id',account).maybeSingle().timeout(const Duration(seconds:4));
  });
});

Future<bool> requireOnlineAction(BuildContext context,WidgetRef ref) async {
  try {
    final ready = await ref.read(onlineActionGateProvider.notifier).check();
    if(!context.mounted) return false;
    if(ready) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(isSpanish(context) ? 'Este cambio requiere conexión. Tu trabajo guardado sigue disponible.' : 'This change requires a connection. Your saved work is still available.')));
  } catch(error) {
    if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(context,error))));
  }
  return false;
}

class OnlineOnlyNotice extends StatelessWidget {
  const OnlineOnlyNotice({super.key});
  @override
  Widget build(BuildContext context) => Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(isSpanish(context) ? 'Se necesita conexión para guardar estos cambios.' : 'A connection is required to save these changes.',style:Theme.of(context).textTheme.bodySmall));
}
