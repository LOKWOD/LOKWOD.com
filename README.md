# LOKWOD.com

This repository is the source/recovery mirror for the public LOKWOD website assets captured from the production application.

## Production hosting

`https://lokwod.com` is a dynamic application and must remain pointed at the production ChatGPT Sites/custom-domain backend while the customer portal, admin routes, authentication callbacks, and server-side application logic depend on that runtime.

Current production DNS target:

- Apex A: `162.159.143.30`
- Apex A: `172.66.3.26`
- `www` CNAME: `custom-domains.chatgpt.site`
- `updates` CNAME: `custom-domains.chatgpt.site`

Do **not** point the production apex to GitHub Pages unless the dynamic backend has first been migrated and all protected routes, server actions, authentication callbacks, dashboards, and OTA services have been recreated on the new runtime.

## GitHub Pages

The files in this repository are useful as a static recovery copy and source-control record. They are not a complete replacement for the production application. In particular, a static host cannot provide the production `/portal`, `/admin`, authentication callback, and other server-side behavior.

The repository intentionally does not contain a `CNAME` file claiming `lokwod.com`.

## Critical production routes to smoke-test after hosting changes

- `/`
- `/login`
- `/portal` (protected; should redirect to sign-in when logged out)
- `/admin` (protected; should redirect to admin login when logged out)
- `/admin/login`
- `/firmware`
- `/support`
- `/beta`
- `https://updates.lokwod.com/hvac/stable/manifest.json`
- `https://updates.lokwod.com/well-monitor/stable/manifest.json`

## Visitor Light

The Visitor Light receiver is separate from this hosting arrangement. The current receiver is `https://lokwod-visitor-beacon.syracuseappraiser.workers.dev`. The live production website must actually load its `beacon.js` script for browser visits to trigger the physical light; having the script only in this static recovery mirror is insufficient.
