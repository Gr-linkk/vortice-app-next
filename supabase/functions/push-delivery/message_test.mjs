import test from 'node:test';
import assert from 'node:assert/strict';
import {fcmMessage,isInvalidToken,notificationTitle} from './message.ts';
test('lock-screen title identifies the event and the payload excludes record contents',()=>{
  const row={id:'delivery',lease:'lease',token:'device',locale:'es',notification_id:'notice',user_id:'account',type:'urgent_fault',reference_id:'sensitive-asset'};
  const message=fcmMessage(row).message;
  assert.deepEqual(message.data,{notification_id:'notice',recipient_id:'account'});
  assert.equal(message.android.notification.tag,'notice');
  assert.equal(JSON.stringify(message).includes('sensitive-asset'),false);
  assert.equal(JSON.stringify(message).includes('urgent_fault'),false);
  assert.equal(message.notification.title,'Falla urgente');
  assert.match(message.notification.body,/actualización/);
});
test('only an unregistered token is retired; service errors stay retryable',()=>{
 assert.equal(isInvalidToken({error:{details:[{errorCode:'UNREGISTERED'}]}}),true);
 assert.equal(isInvalidToken({error:{details:[{errorCode:'UNAVAILABLE'}]}}),false);
});

test('implemented event titles work in English and Spanish',()=>{
  const titles = {
    work_order: ['Work assigned','Trabajo asignado'],
    maintenance_assignment: ['Work assigned','Trabajo asignado'],
    urgent_fault: ['Urgent fault','Falla urgente'],
    maintenance_return: ['Report returned for correction','Informe devuelto para corregir'],
    inspection_due: ['Inspection due','Inspección próxima a vencer'],
  };
  for (const [type,[english,spanish]] of Object.entries(titles)) {
    assert.equal(notificationTitle(type,'en'),english);
    assert.equal(notificationTitle(type,'es-MX'),spanish);
  }
  assert.equal(notificationTitle('future','en'),'New activity in Vortice Next');
});
