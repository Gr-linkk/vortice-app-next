import test from 'node:test';
import assert from 'node:assert/strict';
import {fcmMessage,isInvalidToken} from './message.ts';
test('lock-screen payload is generic and identifies the intended account without business content',()=>{
  const row={id:'delivery',lease:'lease',token:'device',locale:'es',notification_id:'notice',user_id:'account',type:'urgent_fault',reference_id:'sensitive-asset'};
  const message=fcmMessage(row).message;
  assert.deepEqual(message.data,{notification_id:'notice',recipient_id:'account'});
  assert.equal(message.android.notification.tag,'notice');
  assert.equal(JSON.stringify(message).includes('sensitive-asset'),false);
  assert.equal(JSON.stringify(message).includes('urgent_fault'),false);
  assert.match(message.notification.body,/actualización/);
});
test('only an unregistered token is retired; service errors stay retryable',()=>{
 assert.equal(isInvalidToken({error:{details:[{errorCode:'UNREGISTERED'}]}}),true);
 assert.equal(isInvalidToken({error:{details:[{errorCode:'UNAVAILABLE'}]}}),false);
});
