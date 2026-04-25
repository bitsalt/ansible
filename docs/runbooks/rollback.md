# Runbook: Roll back a webapp deploy

Revert a webapp site to a previous known-good image tag after a bad release.

**Related interface:** [ci-deploy.md](../interfaces/ci-deploy.md)
**Related ADR:** [0006 webapp ownership boundary](../adr/0006-webapp-ownership-boundary.md)

---

## Trigger

A webapp site (Node.js, FastAPI, similar) has just deployed a new image and is broken — startup errors, runtime regressions, or end-user reports of failure. The previous image tag is known and was working.

This runbook covers webapp rollback only. WordPress / Laravel rollback is a different shape (image tag in the var file → re-run Ansible). For DB-impacting WP updates, see [wordpress-updates.md § Rollback](wordpress-updates.md#rollback).

## Pre-checks

- [ ] You know the SHA of the last known good image tag (see `/opt/deployments.txt` if it's being maintained, or the app repo's deploy history in GitHub Actions).
- [ ] You have SSH access to the Droplet as `bitsalt` (the `deploy` user is for CI/CD; rollback is usually faster as `bitsalt`).
- [ ] You've identified whether the bad deploy ran any DB migrations. If it did, this runbook is *not* sufficient — the rollback also needs a DB restore. Stop and follow [migration-rollback procedure (TBD)] instead.

## Steps

### 1. Edit the compose file

SSH into the Droplet:

```bash
ssh -p 2222 bitsalt@<droplet>
cd /opt/sites/<site>/
```

Edit `docker-compose.yml`:

```bash
sudo nano docker-compose.yml
```

Find the `image:` line and revert it to the last known good tag:

```yaml
image: <dockerhub-org>/<image>:<previous-good-sha>
```

### 2. Pull and restart

```bash
sudo docker compose pull
sudo docker compose up -d
```

This pulls the previous image (which should already exist on Docker Hub) and recreates the container. Compose's change detection picks up the image tag change.

### 3. Verify

- [ ] `docker compose ps` in `/opt/sites/<site>/` shows the container running with the previous image tag.
- [ ] Logs show clean startup: `docker compose logs -f`.
- [ ] `https://<site-domain>/` loads. Reproduce the original failure path; it should now work.
- [ ] If you have monitoring or external uptime checks, confirm they recover.

### 4. Update `/opt/deployments.txt`

If the deployments log is being maintained:

```bash
echo "$(date -Iseconds) <site> rollback to <previous-good-sha> (from <bad-sha>)" | sudo tee -a /opt/deployments.txt
```

### 5. Communicate

- Notify the app team: which SHA was rolled back from, which SHA is now live.
- File a bug or post-incident note for the bad SHA so it doesn't redeploy.

## Rollback of the rollback

If the rollback itself misbehaves (rare — usually means the "previous good" tag wasn't actually good):
1. Repeat with an earlier known-good SHA.
2. If no earlier good SHA is available, escalate — this is now a deploy outage, not a rollback.

## Post-incident notes

Record the incident details after stabilization:
- What broke and how it was detected.
- Time from deploy → detection → rollback completion.
- Whether the bad SHA had been tested in staging (if applicable).
- Any signal that should be added to monitoring or pre-deploy checks to catch this class of failure earlier.

## Common gotchas

- **Editing compose by hand is sanctioned only during incident response.** ADR 0006 says the app repo owns `docker-compose.yml`. Manual edits during rollback are an exception, not a pattern. After the incident, the app repo should redeploy a fixed version of the previous compose state, not leave the manual edit in place indefinitely.
- **`.env` is *not* part of rollback.** Rolling back the image does not roll back env values. If the bad deploy required `.env` changes (vault edits + Ansible run), those changes persist and may need separate revert.
- **Docker Hub rate limits.** Pulling an old image you haven't fetched recently might hit rate limits on the free tier. Authenticate Docker on the Droplet (`docker login`) if pulls fail.
- **DB migrations are *not* rolled back by changing the image tag.** If the bad deploy ran a migration that changed schema, the previous app version may not work against the new schema. This is why pre-checks ask whether migrations ran.
