# 0015: PM kits, job requirements and scoped stock

Accepted 2026-09-07 for NOW-022, following Garrett's approval to build the
kit-to-stock workflow and deliver an internal Android build.

PM kits remain the editable standard parts list attached to a checklist. Company
managers edit their own kits through the existing editor; shared starters remain
owner-managed. Copying or republishing a procedure carries its kit forward.
Kit contents are separate from immutable published checklist instructions.

New checklist-linked work snapshots requirements when created. Existing jobs may
explicitly import the current kit once. Editing a standard kit never rewrites a
job. Managers adjust required quantities or add requirements on the job; choosing
stock is explicit and units must match. Actual usage records the selected stock
item, including any deliberate substitution, rather than the requested item.

Existing global inventory is provider stock. Managed company jobs use their
client's inventory, with stock separated by location. Reservations reduce
availability without consuming stock; transactions serialize within the stock
owner so separate jobs cannot reserve the same units. Counts cannot fall below
reserved quantities. Receipts use weighted average stock cost; issues use that
cost and returns use the recorded job cost. Provider markup is preserved, while
managed-job parts remain internal costs without customer invoices.

Purchase records are requests, supplier order details and partial/full receipts.
They do not send orders to suppliers. Received stock is reserved explicitly.
Review, closure or cancellation releases unused reservations automatically;
existing deliveries can still be received or cancelled afterward. Actual use and
returns require work in progress or on hold, preserving review/invoice locks.

Stock changes require a connection. Each operation is recorded locally under its
account before sending and uses a stable replay identity. Unknown transport or
gateway outcomes remain pending across restarts; only success or a definitive
database rejection clears the operation. Roles, company scope, revisions and
quantities are checked by the server. Direct deletion of stock-linked job parts
is rejected; unused parts return through the stock workflow.
