import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vortice_app/sync/online_action_gate.dart';

void main() {
  test('online-only action cannot dispatch offline and can retry after reconnect',() async {
    var available=false,writes=0,probes=0;
    final gate=OnlineActionGate(account:'a',currentAccount:()=> 'a',probe:() async {
      probes++; if(!available) throw const SocketException('Offline');
    });
    Future<void> save() async { if(await gate.check()) writes++; }
    await save();
    expect(writes,0); expect(gate.state,ServerConnection.offline);
    available=true; await save();
    expect(writes,1); expect(probes,2); expect(gate.state,ServerConnection.online);
    gate.dispose();
  });
  test('late connection check cannot authorize another account',() async {
    var account='a'; final pending=Completer<void>();
    final gate=OnlineActionGate(account:'a',currentAccount:()=>account,probe:()=>pending.future);
    final check=gate.check(); account='b'; pending.complete();
    expect(await check,isFalse);
    expect(gate.state,ServerConnection.unknown); gate.dispose();
  });
}
