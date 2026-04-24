# Open Issues

Parking lot for bugs and investigations surfaced outside the scope of the
active session. Each entry should be picked up as its own task/session
following the `one-task-per-session` workflow.

---

## dev.bitsalt.com — Let's Encrypt rate limit / cert acquisition loop

**Discovered:** 2026-04-24, surfaced via the freshly-deployed Loki logging
stack (`{service="traefik"}` in Grafana).

**Symptom:** Traefik is repeatedly attempting to acquire a Let's Encrypt
certificate for `dev.bitsalt.com` and has now been rate-limited by LE
("too many attempts"). No cert is being served for the staging host.

**What we already know:**
- [playbooks/vars/sites/bitsalt-staging.yml:5](../playbooks/vars/sites/bitsalt-staging.yml#L5) defines `bitsalt_staging` with `enabled: true`, `site_domain: dev.bitsalt.com`.
- DNS is correct: `dev.bitsalt.com` and `bitsalt.com` both resolve to `45.55.87.133`.
- `bitsalt-staging` is a `webapp` site, so its `docker-compose.yml` (and therefore the Traefik router labels that drive the cert request) lives in the `bitsalt` app repo — not in this Ansible repo.
- The apex `bitsalt.com` cert is working, so Traefik / UFW / port 443 / `acme.json` persistence are all fine in general. This is scoped to the staging subdomain.

**Diagnostic steps when picked up:**

1. Narrow in on Traefik's actual error message in Loki:
   ```
   {service="traefik"} |= "dev.bitsalt.com"
   {service="traefik"} |= "acme" | json
   ```
   The error string tells us which LE rate limit was hit (`too many failed
   authorizations` = 1-hour cooldown per hostname; `too many certificates`
   = weekly). That governs how fast we can iterate on a fix.

2. On the droplet, confirm the backend and the router config Traefik is
   actually seeing:
   ```bash
   docker ps --filter 'name=bitsalt-staging'
   docker inspect <container-name> --format '{{json .Config.Labels}}' | jq .
   sudo ls -la /opt/proxy/letsencrypt/acme.json
   ```
   Checking: is the staging container running at all; does its
   `traefik.http.routers.*.rule` have exactly `Host(\`dev.bitsalt.com\`)`
   and `tls.certresolver=le`; is `acme.json` persisting cert entries for
   other hosts.

3. External probe from a laptop (not the droplet):
   ```bash
   curl -vI https://dev.bitsalt.com 2>&1 | head -30
   dig bitsalt.com CAA +short
   ```
   Tells us what cert (if any) is currently being served and whether a CAA
   record is blocking LE for the whole registered domain.

**Ranked hypotheses (pre-investigation):**

- **Staging container missing or half-wired.** The CI/CD for the staging
  branch may not have pushed an image, or the `bitsalt` repo's
  `docker-compose.yml` has a router label present but mis-shaped (typo
  in `Host()`, or `tls.certresolver` missing). Traefik asks LE for the
  cert as soon as a router references the hostname; if the challenge
  path is misconfigured, retries pile up.
- **`acme.json` churn.** Pre-A4 `recreate: always` on the Traefik task
  used to recreate the container frequently. Bind-mounted file *should*
  have survived, but worth eyeballing. If `acme.json` is small/empty
  relative to the number of sites currently working, that's a signal.
- **A second router requesting a SAN that doesn't exist** (e.g. a
  leftover `www.dev.bitsalt.com` rule with no matching A record).

**Scope when picked up:**

If the fix is in the `bitsalt` repo's `docker-compose.yml` (label hygiene),
it's out of scope for this Ansible repo — handle in that repo's own PR.

If the fix involves the Traefik role (e.g. wanting `acme.json` backups
before any `recreate`, or a safer cert-storage model like a LE staging
endpoint for dev subdomains), scope that as an Ansible task.

Wait for LE's rate-limit window to clear before the final verification
`docker compose up -d` run, or switch Traefik to LE's staging directory
(`https://acme-staging-v02.api.letsencrypt.org/directory`) during iteration
so we're not burning prod limits while debugging.
