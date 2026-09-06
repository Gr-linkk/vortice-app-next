# Next notification and recovery operations

Only target Supabase `hkjpojobdbbtjkhaudki` and Firebase `vortice-next`.
Verify the independent origin and `supabase/.temp/project-ref` before changes.
These are live service changes; routine builds do not deploy them.

The September 6 setup uses `next-push-sender@vortice-next.iam.gserviceaccount.com`
with custom role `projects/vortice-next/roles/nextNotificationSender`. Its only
permission is `cloudmessaging.messages.create`. A notification-only JSON key is
stored in Next function secrets as `FIREBASE_SERVICE_ACCOUNT_JSON`, alongside
`FIREBASE_PROJECT_ID=vortice-next` and random `PUSH_WORKER_SECRET`. Keep key files
in ignored local config. Never commit them, print them, or add them to APKs.

Deploy with the authenticated Supabase CLI from this repository:

```sh
supabase functions deploy push-delivery --project-ref hkjpojobdbbtjkhaudki --no-verify-jwt --use-api
```

The worker implements its own required `x-push-worker-secret` authentication;
`verify_jwt=false` does not make its operations public. Set a Vault secret named
`push_worker_secret` to the exact same value before applying
`schedule_push_delivery.sql`. The named cron job runs every minute. Inspect
`push_deliveries` for failures; do not log device tokens or credentials.
Unauthenticated POST must return 401. Authenticated POST returns claimed and
FCM-accepted counts, which do not prove a device displayed the notification.
`check_push_delivery.sql` provides a read-only schedule/device/delivery summary
without exposing tokens, account identities or secrets.

Android builds take a public client-options JSON through
`VORTICE_NEXT_FIREBASE_CONFIG` with `FIREBASE_PROJECT_ID`,
`FIREBASE_ANDROID_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, and `FIREBASE_API_KEY`.
The guarded build validates the dedicated Next project/app/sender. These options
feed both Dart initialization and native Android background resources. The
service-account key must never be used as this client-options file.

Next Auth allows `com.vortice.next://auth/recovery`. The app requests PKCE reset
links, validates the recovery callback, updates the password, and returns to
sign-in. `tool/e2e/recovery_contract.py` checks the live auth lifecycle using a
disposable account and a generated link without sending email, then removes it.
Customer reset emails remain pending an approved domain and SMTP setup. Existing
Supabase default email service is limited to authorized team addresses.

References: [Supabase SMTP](https://supabase.com/docs/guides/auth/auth-smtp),
[Flutter password auth](https://supabase.com/docs/guides/auth/passwords),
[FCM Flutter handling](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages),
[FCM permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/firebasecloudmessaging).
