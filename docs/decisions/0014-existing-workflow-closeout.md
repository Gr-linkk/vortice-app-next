# 0014: Existing workflow closeout and recovery rules

Status: Accepted
Date: 2026-09-07
Scope: NOW-016, existing workflow stabilization and requested notification titles.

Invoice generation, provider assignment/request conversion, organization saves
and manual meter logging use server transactions. Account-owned operation IDs
survive a lost response; retries return the original result or reject changed
input. Meter writes reject older captured readings and decreasing hours.

Issuing freezes invoice financial values and an export snapshot. Customer owners
and administrators see issued/paid invoices and issued void history, never drafts.
Voiding requires a reason; an issued invoice is corrected by voiding and generating
a new draft on the same work order. Paid invoices cannot be voided in this workflow.
Issue records status only: file sharing and confirmed recipient delivery are
separate actions. Existing invoices receive a current-data snapshot at migration;
this cannot reconstruct unavailable historical details.

Request/report text and photo/signature bytes enter one account-owned queue
before delivery. Begin/upload/finish retries retain the same record identity;
server completion requires its evidence. Rejected bundles stay recoverable and
correction retains their original subject. Read caches expire after 24 hours;
successful authoritative reads remove obsolete mirrors. Access denials and
profile-scope changes clear read caches, never unsent work. While disconnected,
the app cannot discover remote revocation before the next server check or expiry.
Only fully acknowledged queue subjects older than seven days are cleaned up.

This refines decision 0008's generic notification wording: titles may name the
event category in English or Spanish (assignment, urgent fault, returned report,
inspection). Names and job/report content remain inside the authenticated app.
User confirmation proves actual receipt on the existing phone; final-build
permission, tap-routing and process-kill checks require physical acceptance.

Decision 0013 is reserved by the separately authorized UI task; this change does
not integrate its visual work.
