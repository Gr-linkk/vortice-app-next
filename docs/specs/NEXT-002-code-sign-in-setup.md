# NEXT-002.01 — Deferred delivery setup

Garrett deferred email/SMS provider setup on September 12, 2026. The application
and database onboarding flow are implemented; real verification-code delivery
is not accepted. The internal build keeps password sign-in and the configured
test-account switcher available, and explains that code sign-in is unavailable.

The read-only hosted check found email enabled with no custom SMTP sender,
phone sign-in disabled, and neither the magic-link nor signup template exposing
the verification code. No verification messages were sent and no hosted auth
settings were changed. The private local receipt is
`outputs/kanban/auth-config-check.json`.

When provider setup is resumed:

1. Configure the chosen email and SMS services on **Vortice Next**, project
   `hkjpojobdbbtjkhaudki`. Keep provider credentials in the hosted service.
2. Apply `supabase/templates/verification_code.html` to the magic-link and
   signup-confirmation templates, preserving the `{{ .Token }}` placeholder.
3. Verify delivery, expiry, resend limits, contact correction and invitation
   redemption with explicitly selected real recipients. Check both new and
   returning identities; do not infer receipt from an API success response.
4. Enable `VORTICE_EMAIL_OTP_ENABLED` and/or `VORTICE_SMS_OTP_ENABLED` in the
   selected build configuration only after the corresponding channel works.

The hosted code length was eight digits; the UI accepts the configured code
without assuming six digits. The app's resend countdown is a convenience;
the hosted authentication service remains responsible for rate limits and
expiry.

References: [Supabase passwordless email](https://supabase.com/docs/guides/auth/auth-email-passwordless),
[custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp), and
[targeted authentication configuration](https://supabase.com/docs/reference/api/v1-update-auth-service-config).
