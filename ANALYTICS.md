# Analytics

Open the [activity page](https://sintaxerrorpvtltd.github.io/Open-Tangerine/stats.html) for live public release ZIP download counts, stars and forks, plus links to private dashboards.

The [Open Tangerine dashboard](https://us.posthog.com/project/672281/dashboard/2227074) lives in the existing PostHog project (672281). Its `app = open-tangerine` filter separates events from other sites for reporting, not access control. No billing upgrade, private API key or desktop telemetry is required. The browser project token is public and write-only.

Website collection is opt-in. DNT/GPC disable it. The footer allows withdrawal. Only `$pageview`, `ot_download_click`, `ot_releases_click` and `ot_repository_click` are sent using the capture endpoint, without loading the PostHog SDK. No session replay or arbitrary click/text collection exists. Query strings and referrer paths are excluded; only simple `utm_source`, `utm_medium` and `utm_campaign` labels are retained. Visitor identifiers expire after 180 days; tab session identifiers expire after 30 idle minutes. See the website privacy policy.

For future promotion, use links such as:

- Instagram: `https://sintaxerrorpvtltd.github.io/Open-Tangerine/?utm_source=instagram&utm_medium=comment&utm_campaign=launch`
- Reddit: `https://sintaxerrorpvtltd.github.io/Open-Tangerine/?utm_source=reddit&utm_medium=comment&utm_campaign=launch`

Download clicks are not completed downloads. GitHub asset counts include repeat requests, tests and earlier versions; they are not install or unique-user counts. Public source ZIP downloads are not included. Consent and blockers undercount website traffic. Missing referrers appear as direct traffic. Earlier website visits cannot be recovered retroactively.

[GitHub Traffic](https://github.com/sintaxerrorpvtltd/Open-Tangerine/graphs/traffic) reports repository views and clones for a rolling 14 days; it is not website analytics. Stars, forks, issues and pull requests are separate signals of interest, not proof of active users.

Run `node scripts/test-analytics.cjs` for consent and privacy regression checks. The website workflow runs it too.
