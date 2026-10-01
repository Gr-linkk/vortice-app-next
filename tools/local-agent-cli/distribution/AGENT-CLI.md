# Vortice local agent CLI

This internal Linux package contains the office app and a separate agent CLI.
Extract it wherever you keep your apps; the folder may be moved or renamed.
Nothing is installed system-wide. Use an already installed compatible Node 22
or newer. No runtime, package manager dependencies or network download is included.

From the extracted folder:

```sh
./maintenance_local
./bin/vortice-agent help
```

The first command opens the office app; the CLI never starts it automatically.
Fresh agent access is disabled. In the office, open **Agent connections**,
explicitly enable access and create a named connection for selected jobs and
equipment with finite expiry. Read-only is the default; suggested inspection
notes require the optional proposal permission. The office can revoke a
connection or disable access immediately.

Supply the one-time private credential through your agent host's private
`VORTICE_LOCAL_AGENT_TOKEN` environment. Do not put it in arguments, chat or the
settings file. The CLI does not create, store or recover credentials.

Copy **Connection settings for this session** from the office into a private
JSON file owned by your account. Its directory must have mode 0700 and the file
mode 0600. The CLI reads it without repairing permissions. This token-free file
contains the exact office scope and current local socket address. Copy it again
after reopening the office app; addresses change across sessions.

The following paths and IDs are placeholders, not a configured connection:

```sh
./bin/vortice-agent capabilities --connection /private/connection.json
./bin/vortice-agent workspace status --connection /private/connection.json
./bin/vortice-agent equipment list --connection /private/connection.json
./bin/vortice-agent work show --id JOB_ID --connection /private/connection.json
./bin/vortice-agent history list --job JOB_ID --connection /private/connection.json
```

Lists support pagination. Follow `next_cursor`; a changed snapshot requires a
fresh list. Local observations do not establish sync or approval. Approval
belongs to its exact immutable inspection version. The client checks current
capabilities before sending the requested command; the service separately
checks scope, permission, expiry and revocation on every request.

The sole write saves suggested replacement inspection notes for human review:

```sh
./bin/vortice-agent proposals create --input - --operation OPERATION_UUID \
  --connection /private/connection.json < proposal.json
```

`proposal.json` contains `type: inspection.notes`, the selected `job_id`, its
current `expected_document_hash`, and nonempty suggested `notes`. Read the work
first. Choose and retain a stable UUID. After an uncertain response, repeat the
same UUID and exact input; the client does not automatically retry writes.
Changing content under that UUID is rejected.

The office uses **Agent suggestions** to apply or reject notes. Application edits
a draft and does not submit or approve it. The agent's original pending envelope
remains immutable creation evidence; office history shows current human decisions.
No agent command approves work, publishes checklists, changes grants or opens a
database directly.

Output is one JSON result. Exit 0 means a verified result or local help; exit 1
means known service denial; exit 2 means local input/setup refusal; exit 3 means
an unknown requested-command outcome. Errors never echo credentials, raw runtime
diagnostics or private settings. Missing runtime requires a supported existing
Node installation; stale settings require copying the current office settings.

The original application's third-party notices are retained in
`data/flutter_assets/assets/THIRD_PARTY_NOTICES.txt`. This package adds no Node
binary or dependency and makes no new project license decision. Bundle file
hashes detect accidental corruption; they are not a signature or permission grant.
