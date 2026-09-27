# Evidence precedence

Use matching `authorityId`, exact candidate tuple, and newest `generatedAtUtc` together;
do not choose a file by filename alone.

Preferred current surfaces:
1. current release authority and CURRENT-GATES for gate/promotion truth;
2. CURRENT-STATUS for concise current state;
3. FULLRELEASE-SUMMARY for active FullRelease phase/run detail;
4. native run evidence for a specific RunId;
5. finalization-state as a derived compatibility/closeout view;
6. Markdown handoffs/memory as navigation only;
7. historical audit bundles only for historical facts.

A newer file does not override a different candidate tuple. A matching tuple with an older
authority ID can still be stale. Diagnostic-only evidence never earns release proof.

When a derived summary conflicts with current authority, preserve both facts: identify the
derived summary as stale/secondary and use current native authority for the operative
status. Do not edit anything in triage mode.
