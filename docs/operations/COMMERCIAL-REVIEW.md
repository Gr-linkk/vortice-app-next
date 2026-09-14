# Commercial and data-handling review packet

NEXT-009 preparation; not executed agreements or legal clearance.

## Rights and dependencies

The inherited code's separation history is in `FORK_PROVENANCE.md`. It records
provenance and project boundaries, not proof of every contributor's assignment
or commercial rights. No top-level LICENSE/COPYING/NOTICE was found in this
checkout on September 14. Garrett must confirm the rights/agreements covering
the inherited work and decide the distribution license with suitable review.

`python3 scripts/inventory-licenses.py` inventories the resolved runtime graph
from `.dart_tool`, preserving available license text and hashes under
`outputs/next009/licenses/`. This includes SDK/build-support packages reachable
from that graph; it is not an exact binary SBOM or a legal license classification.
Native Android/iOS transitive libraries, generated artwork and customer-supplied
manuals still need the corresponding review. Keep notices with distributed work
as required by each applicable license.
The same tool writes `asset-inventory.json` with tracked asset paths and hashes
as the starting rights-review ledger; it does not invent missing source rights.

Specific decision: `syncfusion_flutter_signaturepad` and its core dependency
use Syncfusion licensing. Obtain and retain proof of the applicable Community
or commercial entitlement, or approve replacement before commercial delivery.
The [package license](https://pub.dev/packages/syncfusion_flutter_signaturepad/license)
and [Community program](https://www.syncfusion.com/products/communitylicense)
are the vendor sources; eligibility cannot be inferred from this repository.
`assets/fonts/Roboto_LICENSE.txt` exists; confirm all shipped fonts/artwork and
manual pages against their source/permission records.

## Customer-facing privacy notice draft outline

Complete the bracketed decisions before legal review or publication:

- Operator/controller: [business legal name, jurisdiction, contact].
- Information handled: account/contact and membership details; company/equipment
  records and meter readings; work assignments, labour, parts and invoices;
  procedures, reports, notes, photos/signatures and uploaded manuals; device push
  registration; account-owned offline copies on supported devices.
- Purpose: provide authorized maintenance/customer-work workflows, access control,
  synchronization and notifications. State any selected operational diagnostics.
- Service providers: Supabase for backend/Auth/Storage and Firebase for push;
  add the selected email/payment/monitoring providers before activation. Confirm
  actual hosting region, contractual terms and data transfers with their accounts.
- Access: organization membership/permissions and authorized customer/provider
  relationships; define and document platform-support access.
- Retention and account closure: [duration, export window, backup expiry,
  offline-device handling, deletion/exceptions]. Existing report/invoice exports
  are not a complete company-data export or deletion service.
- Requests/incidents: [contact and reviewed process for access, correction,
  export, deletion and incident communications]. Do not claim certification or
  blanket compliance from technical tests.

## Pilot agreement draft outline

Record [parties], [effective date], [supported release/devices], [included
workflows and exclusions], [price/currency/tax treatment/payment date],
[cancellation and renewal], [support hours/contact/response expectations],
[customer responsibilities and authorized use], [data ownership/export/closure],
[service changes and outage handling], and reviewed [liability, warranty and
governing terms]. Attach the completed pilot acceptance receipt.

No uptime guarantee, emergency-response promise, accounting/tax certification,
unlimited storage/AI or feature roadmap commitment is selected by this packet.
Garrett supplies business facts and approves the offer; professional review
resolves applicable legal/tax terms before publication or customer reliance.
