# ADR 0008: Centralized logging via Vector to Grafana Cloud Loki

**Status:** accepted
**Date:** 2026-04-24

## Context

A multi-site, single-Droplet Compose environment surfaces operational problems through container stdout/stderr (and, for some classes of issue, through Traefik access logs). Without aggregation, debugging requires SSH'ing in and running `docker logs` per container, which is slow, lossy across container restarts, and unworkable when an issue spans multiple sites or has already scrolled past Docker's default rotation. The first concrete cost of not having this in place was a `dev.bitsalt.com` Let's Encrypt rate-limit issue that was only diagnosable once logs were being aggregated (see `docs/TODO.md` and the 2026-04-24 sprint decisions-log entry).

Requirements for whatever lands:
- Capture stdout/stderr from every site container without per-site wiring (sites churn; the shipper should not).
- Survive container restarts and Droplet reboots cleanly.
- Stay default-off until Grafana Cloud credentials exist in vault, so a fresh clone of the repo doesn't fail mid-play.
- Keep secrets in vault, not in committed config; missing vault values must fail loudly at role entry, not produce a silently-misconfigured pipeline.
- Allow a single Grafana tenant to host multiple deployments (prod, staging, future hosts) without their streams colliding.
- Provide a place to redact obvious PII / credential leaks before they leave the Droplet, on the assumption that not every upstream app is disciplined about this.

This ADR is a **backfill**: the `logging` role was added to `playbooks/roles/logging/` via a remote merge (commits `4689148`, `3a74950`) on 2026-04-24, after Phase 2's Architect step had already produced ADRs 0001–0007. The decision was captured only in the sprint-file decisions log. This ADR records what was built and why, reconstructed from the role's code and the existing architecture prose; choices whose rationale isn't recoverable from those sources are flagged in "Alternatives considered" rather than retrofitted.

## Decision

A single Ansible role, `logging`, deploys a **single Vector container** as a Compose project at `/opt/logging/` that ships to **Grafana Cloud Loki** over HTTPS with basic auth.

Specifically:

- **Single shipper, cross-cutting, not per-site.** One Vector container reads every other container's stdout/stderr by mounting the Docker socket and using Vector's `docker_logs` source (`type: docker_logs` in `vector.yaml.j2`). Adding a site does not require any change to the logging role or its config. The role is single-instance like `traefik`, not looped like `wordpress`/`webapp`.
- **Master switch defaults off.** `logging_enabled: false` in `defaults/main.yml`. `site.yml` skips the role when off, so a fresh clone applies cleanly before Grafana Cloud credentials are populated. Operator opts in by setting `logging_enabled: true` in `group_vars/all/vars.yml` once `vault.yml` carries the three Loki values.
- **Vault-sourced credentials with no role defaults.** `logging_loki_endpoint`, `logging_loki_user`, and `logging_loki_token` are intentionally absent from `defaults/main.yml`; `meta/argument_specs.yml` declares all three `required: true` so a missing value fails at role entry rather than producing a silently-broken pipeline. `logging_loki_token` carries `no_log: true` in the argument spec; the env-rendering task carries `no_log: true` as well. Credentials reach Vector at runtime via the sibling `.env` file referenced by `env_file:` in the compose file — they never appear in `vector.yaml`.
- **Deployment label for tenant separation.** `logging_deployment_label` (default `bitsalt-prod`) is emitted as the `deployment` Loki label on every stream, so a single Grafana Cloud tenant can host prod + staging + future hosts without their streams colliding.
- **PII redaction lives in the Vector pipeline.** A `redact_containers` remap transform in `vector.yaml.j2` scrubs the most common leak patterns (`Authorization`, `Cookie`, `Set-Cookie`, `X-API-Key` headers and key/value pairs in stdout) before the Loki sink. The template comment is explicit that this is a defensive net — apps with structured logging are expected to redact upstream; this catches the rest. Adding a redaction rule is a Vector config edit, not an Ansible structural change.
- **Loki labels are low-cardinality only.** `deployment`, `host`, `site`, `service`, `source_kind`. High-cardinality fields (container IDs, request IDs, etc.) stay in the log body — Loki's index degrades sharply if labels explode.
- **Optional Traefik access-log tail.** A second Vector source (`traefik_access`, `type: file`) is gated behind `logging_traefik_access_enabled` (default false). Flipping it true is a no-op until the `traefik` role is updated to emit a JSON access log to the bind-mounted path; the gate exists today so the wiring is captured but inert.

## Consequences

**Easier:**
- One place to look for logs across the fleet; aggregation outlives container restarts and Docker's local rotation.
- Adding a site requires zero logging-role changes — `docker_logs` picks up the new container automatically (modulo the `exclude_containers: [logging-vector]` self-loop guard).
- Operators without Grafana Cloud credentials can still run a clean apply; logging stays off until they explicitly enable it.
- Secrets boundary is sharp: missing vault values fail at role entry, not deep inside Vector's startup; the token never lives in templated config.
- Multi-environment separation (prod / staging) is a one-label change, not a separate Loki deployment.
- Defensive PII scrub is centralized — fixing a redaction rule is one config change, not a fan-out across every app.

**Harder:**
- Mounting the Docker socket into the Vector container is a non-trivial trust grant. It's a read path in practice (Vector consumes log streams), but the socket itself is not constrained in the way the Traefik socket-proxy constrains Traefik's access. Acceptable today; revisit if the threat model changes or if Vector's own attack surface expands.
- The "everything via the Docker socket" design means Vector must be running for any log to be captured. A Vector outage is a logging outage; logs produced during that window are lost (Vector does not back-fill from `docker logs` history beyond what's currently buffered). Acceptable for our diagnostic-grade use case; not acceptable for compliance/audit-grade logging without a different design.
- The default Vector image tag (`timberio/vector:0.47.0-alpine`) pins us to one Vector version per role release; upgrading is an Ansible change, not a passive pull.
- PII redaction in the pipeline is best-effort. Structured leaks (a credential embedded in a JSON field name we don't match, base64-encoded payloads, etc.) will pass through. The right place for hard guarantees is upstream in the app — the redact transform is explicitly a backstop.
- An external SaaS (Grafana Cloud) is now in the critical path for log retention. Outage there means logs queue locally in Vector's disk buffer and may be dropped if the outage outlasts buffer capacity.
- One more thing for an operator to learn (Vector config, VRL transform language, Loki label cardinality rules) before they can extend the pipeline.

**Reconsider if:**
- Compliance or contractual logging requirements emerge that need guaranteed delivery, longer retention, or audit-grade integrity. Would push toward a different sink and likely a different shipper architecture (with persistent queueing, dual-sink, etc.).
- Log volume or per-stream cardinality outgrows the Grafana Cloud free / paid tier in use, or per-line cost from Grafana Cloud becomes a meaningful budget item.
- A second Droplet or multi-region topology lands; the "single Vector container per host" pattern still works but the deployment-label / host-label scheme would want re-examination.
- Vector itself becomes a maintenance burden (upgrade churn, breaking config changes) — would justify revisiting the shipper choice against current alternatives (Fluent Bit, OTel Collector, Promtail, etc.).
- The Docker-socket trust grant becomes uncomfortable — would push toward a sidecar-per-site or a socket-proxy in front of Vector.

## Alternatives considered

- **Self-hosted Loki on the Droplet (or a sibling host).** Avoids the SaaS dependency and per-line cost. Adds storage, retention, and upgrade burden — the same calculus that drove ADR 0001 (no DB containers) away from self-hosted state. Not chosen.
- **ELK / Elasticsearch + Kibana.** Heavier-weight than the use case warrants on a single 4–8 GB Droplet; would either need a managed offering or a separate host. Not chosen at this scale.
- **CloudWatch Logs / DO equivalent.** Possible, but ties logging into a separate cloud account model. Not chosen.
- **Per-site logging sidecars.** Would require touching every site's compose file. Rejected on the same "per-site wiring tax" grounds that drove the cross-cutting role design.
- **Promtail or Fluent Bit instead of Vector.** Both are reasonable shippers for the Loki sink. **Rationale for choosing Vector specifically over these is not recoverable from the role's code, the sprint decisions log, or existing architecture prose** — the choice was made out-of-band before the role was merged. Captured here as a known backfill gap; if the choice should be defended on different grounds in a future review, this ADR should be updated rather than re-litigated.
- **Grafana Cloud Loki vs. an alternative managed log destination.** Same backfill gap as above: the destination was settled before this ADR was written. Vector itself is sink-agnostic, so a future change of destination is a config-level change in `vector.yaml.j2`, not a re-architecture.
