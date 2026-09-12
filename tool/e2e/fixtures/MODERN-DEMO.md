# Modern demo fixture

This explicit Next-only fixture creates five fresh identities, two companies,
their accepted service relationship, and one synthetic truck at 62,000 km.
It never changes the existing development accounts or fleet. The four fleet
roles are Company Owner, Supervisor, Mechanic and Operator; the second company
has a Company Owner with provider work and billing enabled.

From the guarded independent Next clone after all current migrations:

1. Run `python3 tool/e2e/fixtures/prepare_modern_demo.py prepare` using Python
   with bcrypt or Linux crypt Blowfish support. It verifies the clone/origin and
   config target, then writes ignored `work/modern-demo-private/apply.sql` and
   pending passwords. Re-running refuses to replace those prepared credentials.
2. Review and explicitly apply that additive SQL with the existing Next CLI.
   Its transaction refuses every existing fixture ID/email, uses bcrypt hashes
   in auth.users, and exercises company creation, invitations, relationship
   acceptance and meter configuration through their normal functions.
3. Run `python3 tool/e2e/fixtures/prepare_modern_demo.py activate`. Only after
   all five password logins return their exact expected identity does it merge
   credentials into ignored `config/vortice-next.local.json`. It preserves the
   existing account entries. No email, SMS, or delivery test is sent.
4. Follow `tool/e2e/README.md` for fonts, a fresh output directory, and the local
   config. Run `flutter test tool/e2e/modern_membership_test.dart
   --dart-define-from-file="$VORTICE_E2E_CONFIG" --reporter expanded` as a single
   command. This connected check switches via the actual picker, checks saved
   modern roles, company separation, permission flags and Assets/meter reads,
   and records screenshots. It does not create work or notifications.

The private SQL and passwords stay ignored. The template and preparation script
contain no live secrets. Physical Android workflows still require a debug APK
built with the activated config; the picker labels identify the new demo roles.
