# Open Tangerine analytics

Website analytics run on **GoatCounter**, in a dedicated Railway project. No PostHog integration remains. Never reuse Some1.help’s infrastructure or analytics credentials.

- [Activity page](https://sintaxerrorpvtltd.github.io/Open-Tangerine/stats.html): public release ZIP requests, stars, forks, issues, links to private reports.
- [Private website dashboard](https://goatcounter-production-7a2a.up.railway.app/): visits, referral sources/campaigns, approximate countries, and explicit download/repository/release clicks.
- [Railway project](https://railway.com/project/5db2c531-9d9d-43fb-a7ca-0840f5fabac2): Open Tangerine Analytics, production environment `a7705471-a719-41ff-848d-17f96c687930`, service `2db63b88-f2dc-4698-8d65-41c34560b2e8`.
- SQLite lives on its own persistent volume at `/home/goatcounter/goatcounter-data/db.sqlite3`. A volume is persistence, not a backup. Railway usage charges apply.
- Sign-in email: `sintaxerror.pvt.ltd@gmail.com`. The generated password is in this service’s Railway variable `GC_ADMIN_PASSWORD`. Never commit or publish it. SMTP password recovery is not configured.

Collection is opt-in; DNT/GPC override consent. The footer supports withdrawal. Only the consent choice and expiry (180 days) are stored in the browser. Old visitor/session identifiers are removed. No SDK or replay is loaded. The count endpoint receives only clean paths, a referrer domain or simple `utm_source` label, an event flag/title and random cache buster. It receives normal network IP/browser information; GoatCounter estimates visits without persistent client IDs. Hosting logs have separate retention.

Events: page path, `ot_download_click/<release>`, `ot_releases_click`, `ot_repository_click`. Use `?utm_source=reddit` or `?utm_source=instagram` on shared links. QA events use `utm_source=qa`. Click counts are not completed downloads or installs; repeated clicks may be deduplicated by GoatCounter. Analytics cover only consenting visitors and cannot recover earlier traffic.

[GitHub Traffic](https://github.com/sintaxerrorpvtltd/Open-Tangerine/graphs/traffic) reports repository views/clones/referrers for a rolling 14 days. Release ZIP counts include repeat downloads and QA. Stars/forks/issues/PRs are separate interest/contribution signals. The Mac app sends no analytics.

Run `node scripts/test-analytics.cjs`, `node scripts/test-site.cjs`, and `node scripts/test-demo.cjs` before publishing. Verify the deployed tracker and a QA visit in the private dashboard.

## Migration record

A brief initial setup incorrectly used existing PostHog project 672281 and created draft dashboard 2227074, filtered by `app=open-tangerine`. QA pageview/download-click events were sent. The user rejected PostHog entirely. The token was removed and collection disabled in commit `17a2de21b9583a3ad5833be70f6dc650f30f9212`, before this independent GoatCounter integration. The old draft dashboard and QA events were not deleted. Some1.help code, existing dashboards, settings and billing were not modified. Do not reconnect this website to that project.
