# NOW-004: internal dev persona login

Garrett requested restoring password autofill in the login logo's Easter egg
panel after installing build 1.1.0+2. Selection previously filled the email and
explicitly cleared the password.

The internal build now loads `DEV_LOGIN_PASSWORDS`, a JSON-encoded email/password
map, from ignored `config/vortice-next.local.json`. The existing guarded debug
builder passes this configuration. Only the six displayed Next mock accounts
are configured; personal credentials are excluded. Source and example config
contain no account passwords. This explicit internal-testing request authorizes
embedding those mock passwords in Garrett's debug APK. Anyone possessing that
APK can extract its test credentials, so this configuration is not for public
distribution.

Both the panel and environment value are gated by `kDebugMode`. Parsing also
requires the exact authorized Next URL. Missing, malformed or inappropriate
configuration yields no autofilled password. Selecting an account still leaves
the final Sign in action to the user.

Verification: all six existing mock accounts authenticated successfully against
Next and returned the expected role; verification sessions were signed out.
Widget coverage opens the logo panel, switches personas, checks both fields and
submits the selected credentials. Configuration coverage checks release/host
gates and malformed values. Focused analysis and repository guardrails passed.

Follow-up device report: build 1.1.1+3 showed `Invalid API key` (401). Its
runtime `AppConstants.supabaseAnonKey` still contained a literal redaction
placeholder, so direct config-based HTTP checks did not verify the actual app
wiring. A Flutter/Dart smoke test using the same AppConstants and Supabase client
reproduced the exact 401. Replacing that constant with the build-time environment
value made all six logins pass through the app configuration. The APK helper now
runs the runtime-config regression test using the same define file before building.

Corrected delivery target: internal Android 1.1.2+4, same application ID and debug signing,
copied to Garrett's phone Downloads. The earlier fault/availability backend
migrations remain separate and pending explicit hosted approval.

Delivery verified 2026-09-05: phone SHA-256 matches the local APK. The signing
certificate matches build 1.1.0+2. An installer open request was sent; installation
and use of this updated build on the device still await user confirmation.

Corrected 1.1.2+4 delivered 2026-09-05 with a matching phone checksum. The APK
contains the configured API key, excludes the placeholder, retains all six dev
passwords, and uses the same signing certificate. Actual device login on this
replacement build still awaits user confirmation; the app-config Dart login
smoke test passed all six roles.
