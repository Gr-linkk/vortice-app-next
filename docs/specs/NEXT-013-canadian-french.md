# NEXT-013: Canadian French and translation polish

Requested September 24, 2026. Garrett explicitly requested Luna or a lower-cost
model for French, then independent review, thorough testing and polish. The
parent task owns integration and acceptance; delegation does not constitute
verification.

## Contract

- Preserve English and Spanish. Add persisted French selection at login and
  Settings with each language named in that language.
- Translate all generated strings and ordinary workflow labels. Use consistent
  equipment and work-order vocabulary. Do not translate or overwrite customer
  descriptions, manuals or checklist answers automatically.
- Verify placeholders, language switching, persistence, ordinary navigation and
  readable fields at 390-pixel normal text and 320-pixel 200% text. Include
  French in the final connected role walkthrough and keep phone acceptance
  separate from rendered checks.
- Audit inline bilingual strings, date/status helpers and server-email language
  choices; a complete ARB file alone does not mean the whole app is translated.

## Implementation and review — September 25

French is selectable at sign-in and Settings and persists across restarts. Luna
translated 340 generated strings and ordinary navigation, equipment, work,
parts, reports and organization pages. The parent independently reviewed and
corrected unreachable French conditionals, two accidental English changes,
shared Home/offline status messages, and long billing labels. The selected
vocabulary uses Équipements, Bons de travail and Défaillances; user-authored
procedures and descriptions retain their original language.

Connected, read-only walkthroughs of five roles passed in French at 390 pixels
and normal text and at 320 pixels and 200% text. These used real Next sessions,
asserted the selected locale, followed actual navigation, and opened equipment,
work forms, settings and permitted provider work. Captures and logs:
`outputs/french-localization/connected-normal/` and `connected-large/`.
The parent visually inspected the large-text Home and invoice/report screens.
Native CAD forms, PDF exports (including three-page long content) and spreadsheet
amounts were reviewed separately under `outputs/next011/native-cad/`. Report
currency switching preserves historical CAD/USD amounts.

Remaining translation boundaries: less-common setup/recurrence/coordination
fields still need a complete editorial sweep; report CSV headings and hosted
invitation/OTP email preferences currently support English/Spanish. Customer
content, manuals and stored procedure text are not automatically translated.
These limits prevent claiming complete French coverage. Physical French phone
acceptance is separate from the rendered, connected walkthroughs.
