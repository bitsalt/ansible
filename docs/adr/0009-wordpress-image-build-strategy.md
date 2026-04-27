# ADR 0009: WordPress image build strategy — accept the in-role build, annotate the carve-out

**Status:** proposed (revised 2026-04-27 after operator-ownership clarification; see Revision history)
**Date:** 2026-04-27

## Context

The `wordpress` role's `Start WordPress site` task uses `community.docker.docker_compose_v2` against a compose file whose `wordpress` service is declared with `build: .` (a tiny Dockerfile that wraps the upstream `wordpress:<tag>-fpm` image with PHP-FPM pool tuning — see `playbooks/roles/wordpress/templates/Dockerfile.j2` and `docker-compose.yml.j2`). On every `ansible-playbook --check --diff`, that task reports `changed`, even when nothing has drifted. The reason is the same family of limitation captured in `~/projects/agent-knowledge-base/lessons/community.docker/check-mode-fidelity-pre-3-10.md` and `pull-always-with-pinned-tag.md`: compose v2 cannot prove a `build:` stanza would yield an unchanged image without actually running the build, so check-mode marks the task `changed`. This is the last item blocking sprint Task B7 (`changed=0` on a second consecutive apply) for the two migrated WP sites; ~11 more sites are queued behind Task B closure and the FR9 backup role.

Three options were filed in OQ-7:

- **(a)** Accept the false positive, annotate it the way the Traefik handler carve-out is annotated (per the A4 work, 2026-04-24), and move on.
- **(b)** Replace `build: .` with a pre-built `bitsalt/wordpress` image pushed to Docker Hub. Eliminates the build from the apply path. Originally framed as ADR-0006-aligned (webapp-style ownership boundary); see Revision history for the corrected framing as *operator-owned-image*, which is a different shape.
- **(c)** Condition the `Start` task on `dockerfile_result.changed or env_result.changed or compose_result.changed`, accepting that those are the only legitimate triggers for a recreate.

A fourth path is also visible from the role code:

- **(d)** Keep the build in the role but split it from the apply. A new `wordpress : Build image` task with `community.docker.docker_image_build` runs only when `dockerfile_result.changed`, tags the image as `bitsalt/{{ item.site_name }}-wordpress:<sha>`, and the compose file references the tag instead of `build: .`. Compose v2 *can* introspect a pinned-tag `image:` line, so check-mode goes quiet without leaving the role.

### Constraints carried in

- **Operator-as-image-owner is the model.** Per Jeff's 2026-04-27 clarification: he and the DevOps role are the only point of change for WP CI/CD. Customers own database content and the bind-mounted `wp-content/`. There is no separate WP app team. ADR 0006's webapp boundary works because app-team CI is *external and uncoordinated* with apply; here, image ownership and apply are operated by the same hands. Whatever boundary we pick must be honest about that — operator-owned-image is not app-team-owned-image, and the ADR-0006 framing does not transfer cleanly. Coordination properties differ.
- **Hard constraint on apply-time blast radius.** Per the same clarification: when the playbook runs to fix one site, unchanged sites must not have their containers restarted. This is a requirement on real-apply behavior, not on `--check` output. Whichever option we pick has to meet it.
- ADR for A4 (`recreate: auto`, 2026-04-24 entry) already establishes the project pattern for "compose v2 can't introspect this; carve out with an explicit block-comment rationale." The Traefik handler is the precedent (one carve-out line).
- The `community.docker` 5.2.0 lessons explicitly call out `build: always`-shaped false positives as a separate, accepted concern; the role only sends `build: always` when `dockerfile_result.changed` (role `tasks/main.yml` lines 75–78), and otherwise sends `build: policy`.
- Sprint pressure is real: Task B7 is the last gate before backup-role work and the ~11-site WP migration backlog. At steady state there will be ~13 WP sites; recap-line scaling is now an explicit dimension.

### What `recreate: auto` + `build: .` actually does at apply time (not check)

This is the load-bearing empirical question. The hard constraint is about apply behavior, not `--check` output. Evidence assembled from the role code, the module's `build:` policy semantics, and the two `community.docker` KB lessons:

1. The `Start WordPress site` task passes `build: "{{ 'always' if dockerfile_result.changed else 'policy' }}"`. The inline comment (role main.yml:75–78) explicitly states: "Force a rebuild only when the Dockerfile changed; otherwise fall back to compose's own policy (builds only if the image is missing locally)."
2. The KB lesson `check-mode-fidelity-pre-3-10.md` line 51 specifically scopes the surviving check-mode false positive to `build: always` and `pull: always`, not to `build: policy`. Compose's `policy` default is `missing` — build only if the local image is absent.
3. After the first apply, the per-site image (`{{ item.site_name }}-wordpress`) is present locally. With `build: policy` and an unchanged Dockerfile, compose skips the build at apply.
4. With `recreate: auto` (A4), compose recreates only when its config hash shows drift (rendered compose file or `env_file` changed). Neither changes on a no-op apply for an unrelated site.

**Conclusion:** at apply time, with the Dockerfile unchanged, the container is *not* recreated. The `changed` line that appears under `--check --diff` is cosmetic — a check-mode artifact of compose v2's inability to prove the `build:` stanza would be a no-op without running it. The hard apply-blast-radius constraint is met by the existing role under Option (a).

**Caveat: this is inference from role code + module behavior + KB lessons, not a direct empirical capture.** A confirming `.checks/oq-7-apply-no-op.log` capture (one site's playbook applied real, no change to any WP-related variable, second consecutive apply shows the WP `Start` line as `ok` and no container restart in `docker ps` uptime) is the authoritative test. **This capture is required before this ADR moves from `proposed` to `accepted`** — see Follow-ups.

If the capture contradicts this inference (i.e., real apply *does* recreate the container despite `build: policy` + unchanged Dockerfile), Option (a) fails the hard constraint and is eliminated. The fallback decision tree is in the Revision history.

## Decision

**Adopt Option (a), conditional on apply-time verification: accept the in-role `build: .` behavior, annotate the `Start WordPress site` task with a block comment cross-referencing this ADR and the `check-mode-fidelity-pre-3-10.md` / `pull-always-with-pinned-tag.md` lessons, and treat the recurring `changed` on WP `Start` lines as a known-and-explained carve-out — same shape as the Traefik handler carve-out from A4.**

This decision is conditional. The `proposed → accepted` transition is gated on a real-apply capture demonstrating that the WP container is not recreated when the playbook runs and no WP variable has changed. If that capture shows recreation, Option (a) is eliminated and Option (d) becomes the recommended path (see Revision history § Fallback).

Implementation note for the Developer session that lands this:

- The annotation goes on the `Start WordPress site` task in `playbooks/roles/wordpress/tasks/main.yml`. It must explicitly say (i) why the line reports `changed` under `--check` (compose v2 can't introspect `build:`), (ii) that the existing `build: "{{ 'always' if dockerfile_result.changed else 'policy' }}"` gate already prevents unnecessary real rebuilds, (iii) that real-apply behavior leaves unchanged containers untouched (so cross-site blast radius is bounded), and (iv) that this is intentional, not a bug to fix.
- Task B7's exit criterion is restated: a steady-state apply reports `changed` *only* on the WP `Start` lines (one per migrated site, currently 2, growing toward ~13) and the Traefik handler line, with no other unexplained `changed` lines. That is the closure shape, not literal `changed=0`. PM should land this restatement in the sprint file alongside OQ-7's resolution.

### Why (a) wins over (b), under the revised operator-ownership framing

The original draft rejected (b) by appealing to ADR 0006's app-team-CI boundary, which Jeff's clarification correctly identified as not the right frame. The honest framing for (b) is **operator-owned-image**: the same hands that run apply also run `docker build && docker push`. Re-evaluated on that basis:

- **The build is already operator-controlled and already coordinated through Ansible.** The Dockerfile's `FROM {{ item.wp_image }}` is pinned in each site's vars file. WP-core or PHP-base bumps happen by editing the vars file; that re-renders the Dockerfile, fires `dockerfile_result.changed`, fires `build: always`, and fires a recreate via `recreate: auto` against the new image. There is no "silent staleness" risk to relocate, because there is no place for staleness to hide — the image-source-of-truth is already an Ansible variable. Option (b)'s original objection (silent staleness) is genuinely weakened by Jeff's clarification, just as the prompt anticipated. But the corollary is that Option (b)'s *benefit* (eliminate the build from apply) doesn't actually improve coordination — it relocates a coordinated rebuild to a coordinated `docker push`, which is the same problem with a different name.
- **(b) introduces a new sync hazard that doesn't exist under (a).** Under (a), changing `wp_image` in a vars file is one edit, in one place, and the next apply rebuilds and recreates. Under (b), changing `wp_image` requires *two* coordinated actions: edit the vars file *and* `docker build && docker push bitsalt/<site>-wordpress:<new-tag>`. If the operator forgets the second step, the next apply pulls the previous tag (success-shaped: nothing visibly broke; image is just stale). That is a worse failure mode than (a)'s noisy `--check` line.
- **No new infrastructure required.** Docker Hub repos (per-site? shared with site-name suffix?), tag policy, and a publish runbook all become live questions under (b). Under (a), zero new infrastructure.
- **Sprint pressure.** Same as before: B7 is the gate; (a) closes it in ~30 minutes; (b) does not.

### Why (a) wins over (c)

Unchanged from the original draft. Option (c) — gate `Start` on `*_result.changed` — has subtler failure modes than its phrasing suggests:

- **It changes the semantics of `Start`** from "ensure the stack is up" to "start the stack only when one of these three template tasks reported a write." A live container that died for unrelated reasons (OOM, daemon restart) and needs `state: present` to bring it back up would not be brought back, because no template task reported `changed`. The `Start` task's job is convergence; gating it on prior-task state breaks that.
- **It silences a real check-mode signal** by suppressing the task entirely under `--check`, which is *worse* than (a)'s false positive — a future operator reading the recap can no longer tell whether the WP stack is even being considered. (a) leaves the line; (a)'s annotation explains it.
- **It interacts badly with handlers and `recreate: auto`.** The current code already correctly threads `dockerfile_result.changed` into the `build:` argument; doing the same on `when:` for the entire task duplicates logic and creates two places to keep in sync.

### Why (a) wins over (d) — for now, with an explicit escalation trigger

This is the part of the analysis that moved most under Jeff's clarification. (d) is genuinely the cleanest long-term shape, and the 13-site recap-scaling argument cuts in (d)'s favour:

- Under (a) at steady state: ~13 annotated `changed` lines on every `--check`, plus the Traefik handler line. The operator must mentally filter ~14 explained-but-noisy lines to spot a real one. That's quantitatively worse than the precedent (one Traefik line).
- Under (d) at steady state: 0 WP-build lines (the pinned-tag `image:` reference lets compose v2 introspect cleanly), plus the Traefik handler line. The recap is genuinely quiet.
- Under (b) at steady state: also 0 lines, but with the sync-hazard cost above.

What keeps (a) ahead today is sprint capacity and reversibility:

- **Reversibility is symmetric, cost is not.** (a) is ~30 minutes of annotation; (d) is a half-day refactor (new `docker_image_build` task, tag scheme decision, compose template change, role-level testing across both currently-migrated sites). The (a) → (d) migration cost later is roughly the same as the cost now, because the refactor is at the role level and applies to all sites at once. Doing it now eats sprint-1 capacity that B7 needs for the migration backlog.
- **Quantitative recap pain is bounded today.** With 2 migrated sites, (a)'s recap shows 2 WP `Start` lines + 1 Traefik handler line = 3 explained lines. That is at the edge of what a single annotation pattern can carry, but it is not yet broken.

**Escalation trigger to (d), explicit:** When the recap exceeds 5 explained `changed` lines (roughly: 5 WP sites migrated past the current 2), or when an operator reports having to scan past WP-build noise to spot a real change, (d) is the recommended path. Re-invoke this ADR at that point. The (d) refactor is a single role-level change; doing it once at the 5-site mark covers all subsequent migrations.

This is a sharper escalation trigger than the original draft's "~20 sites or Dockerfile complexity grows." The original was too lax given Jeff's clarification that 13 is the steady-state count, not 20+.

## Consequences

**Easier:**

- Task B7 closes with one annotation commit and a verification capture. The ~11-site migration backlog and the FR9 backup role are unblocked on the timeline they need to be unblocked on.
- No new infrastructure (Docker Hub repos, image-publish CI, runbooks, interface docs) added to the project's surface area. This sprint stays focused on drift reconciliation, not new boundaries.
- The project's "compose v2 can't introspect X → annotate carve-out" pattern is reinforced rather than fragmented across competing strategies.

**Harder:**

- The `--check --diff` recap will permanently include up to N `changed` lines for N migrated WP sites' `Start` tasks. Operators reading the recap must know to discount those — same discipline already required for the Traefik handler. The annotation is the documentation of that discipline. **This pain scales linearly with site count and is bounded by the explicit (d)-escalation trigger above.**
- A future WP-core or PHP-base bump still triggers a real rebuild on the box on next apply. That is by design and is correct behavior, but it is slower than a `docker compose pull` would be.
- Anyone hoping to use raw `changed=0` as a binary "is the system converged?" signal cannot. Closure is "no *unexplained* `changed` lines."

**Reconsider if:**

- The verification capture (see Follow-ups) shows that real apply *does* recreate unchanged containers despite `build: policy` + unchanged Dockerfile. In that case Option (a) fails the hard constraint and Option (d) is the new recommendation.
- Migrated WP site count crosses ~5 (sharper trigger than the original ~20). At that point, (d) (split build from apply, reference a pinned tag) becomes worth its refactor cost. The escalation point is recap-readability, not site count for its own sake.
- A real operator-side image-publish flow appears (e.g., a desire to standardize `wp-cli` plugin sets at build time, or a security-driven requirement to scan WP images in CI). At that point (b) gets a real reason to exist beyond "eliminate `--check` noise" — revisit.
- The carve-out annotation drifts from the actual behavior (e.g., the `build:` gate is changed and the comment isn't updated). The annotation is load-bearing; if it stops being trustworthy, treat as a real bug.

## Alternatives considered

- **Option (b) — pre-built `bitsalt/wordpress` image on Docker Hub.** Rejected as the sprint resolution. Under the revised operator-ownership framing: it does not relocate a real coordination problem (the build is already coordinated through Ansible via the `wp_image` vars-file pin), and it introduces a new vars-file-vs-Docker-Hub-publish sync hazard that doesn't exist today. The original "silent staleness" objection is weakened but the new "two-step coordinated edit" objection takes its place.
- **Option (c) — gate `Start` on `*_result.changed`.** Rejected. Changes the semantics of a convergence task into a triggered task; breaks the case where a container is down for reasons unrelated to template state; suppresses the very `--check` signal that (a) preserves and explains.
- **Option (d) — split build from apply, reference a pinned tag in compose.** Rejected for *this sprint* as too large a refactor for the convergence improvement it delivers, but explicitly named as the right path once the explained-line count crosses ~5 sites. This is the cleanest long-term shape and the ADR's escalation trigger is set accordingly.
- **Disable `--check` for this task.** Considered briefly and rejected: the task's real-apply behavior is correct; suppressing check-mode entirely loses signal for a problem that doesn't exist.

## Follow-ups

For PM to route after Jeff approves this ADR:

1. **Developer task (new, sprint-current):** Land the annotation on `playbooks/roles/wordpress/tasks/main.yml` `Start WordPress site` task. Cross-reference this ADR (0009) and the two community.docker KB lessons. The annotation must cover all four points listed in the Decision section's implementation note. Branch shape: `developer/ansible/oq-7-wp-build-annotation`. Should be ~30 minutes plus a `.checks/post-oq-7.log` capture.
2. **Verification capture (gating for `proposed → accepted`):** A real-apply capture (`ansible-playbook site.yml --ask-vault-pass --tags wordpress` with no WP-vars change), recorded as `.checks/oq-7-apply-no-op.log`, plus `docker ps --format '{{.Names}}\t{{.Status}}'` before-and-after to confirm WP container uptime is unbroken. If the capture shows the WP `Start` task did not recreate the container, this ADR moves to `accepted`. If it did, this ADR is rewritten to recommend Option (d). DevOps to capture, since they have the Droplet credentials.
3. **PM task:** Land OQ-7 resolution in `docs/ansible.md` Open Questions table (status: resolved by ADR 0009 *pending verification*; resolution: option (a) — accept and annotate, with explicit escalation trigger to option (d) at ~5 migrated WP sites). Restate Task B7's exit criterion as "no *unexplained* `changed` lines" rather than literal `changed=0`, and capture the WP `Start` lines + Traefik handler line as the explained carve-outs.
4. **Tech Writer (deferred, low-priority):** When the recap-explanation discipline crosses a third instance, the operator-facing `docs/getting-started.md` or `docs/onboarding.md` should grow a brief section on "explained vs. unexplained `changed` lines" so a fresh operator doesn't read carve-outs as failures. Not gated on this ADR; mention in the next sprint review.
5. **No new interface doc warranted.** Option (a) introduces no new boundary or contract; `docs/interfaces/` is unaffected.
6. **No coding-standards addendum change warranted.** The existing addendum §4 already covers `recreate: auto` and the carve-out discipline; this ADR is an instance of that discipline, not a new rule.

### Stale-doc flags (do not edit; route to originating role)

- **None requiring re-invocation.** ADR 0006 is not stale; its scope is correctly limited to webapp sites with per-repo CI, and this ADR explicitly affirms that limit and clarifies why the WordPress shape is *operator-owned-image*, not *app-team-owned-image*. The architecture doc's WordPress section accurately describes the FPM + sidecar shape; no update needed unless implementation diverges.

## Revision history

### 2026-04-27 (revision 1, post-Jeff-clarification)

This ADR was first drafted earlier on 2026-04-27 with a recommendation of Option (a) framed primarily on "ADR 0006's boundary doesn't transfer because there is no other party to own the image." Jeff supplied two clarifying constraints that required the analysis to be redone:

1. **Operator-as-image-owner is the actual shape.** He and the DevOps role are the only point of change for WP CI/CD — there is a single party owning the image, just not a *separate* party. The original framing ("no one owns the image") was wrong; the correct framing is "operator owns the image, distinct from any app team." This is not the same shape as ADR 0006 and the ADR now says so explicitly.
2. **Apply-time blast radius is a hard constraint.** When the playbook runs to fix one site, unchanged sites must not have their containers restarted. This made the question "does `recreate: auto` + `build: .` recreate unchanged containers at *apply* time, or only report `changed` cosmetically at `--check` time?" load-bearing.

**What changed in the analysis:**

- A new "What `recreate: auto` + `build: .` actually does at apply time" section was added, working through the role code, module semantics, and KB lessons to conclude that apply-time behavior on unchanged Dockerfiles uses `build: policy` (not `build: always`), skips the build, and `recreate: auto` leaves the container alone. The hard apply-blast-radius constraint is met under (a).
- The Decision is now explicitly conditional on a real-apply verification capture (Follow-up #2). This was not in the original draft. If the capture contradicts the inference, the fallback below applies.
- The (b) rejection was rewritten. The original "silent staleness" objection is honestly weakened by operator ownership (because the operator is the publisher and there is no silent path) — but a new objection takes its place: the build is already coordinated through Ansible via the `wp_image` vars-file pin, so (b) doesn't reduce coordination problems, it relocates them, and it introduces a new vars-file-vs-publish sync hazard.
- The (d) rejection was sharpened, not weakened. The original draft set the (a) → (d) escalation trigger at "~20 sites or Dockerfile complexity grows." Jeff's clarification that 13 is the steady-state count made that trigger too lax. The revised trigger is "~5 migrated WP sites" — at that point the recap-noise becomes legitimately hard to scan and (d)'s refactor cost is justified.
- Recommendation did **not** flip. Option (a) still wins for sprint 1, on tighter and more honest grounds. The two dimensions that drove the (revised) decision: (i) the build is already operator-coordinated through Ansible variables, so (b) doesn't actually move drift anywhere useful, and (ii) sprint-1 capacity is the binding constraint and (a) closes B7 in 30 minutes plus a verification capture, where (d) is a half-day refactor.

### Fallback (in case the verification capture invalidates Option (a))

If `.checks/oq-7-apply-no-op.log` shows the WP `Start` task recreating the container at apply despite `build: policy` and an unchanged Dockerfile, Option (a) fails the hard apply-blast-radius constraint and is eliminated. In that case:

- **Option (d) becomes the recommendation.** It is the only option that meets the hard constraint without introducing the (b)-style sync hazard. Refactor: add a `wordpress : Build image` task using `community.docker.docker_image_build`, gated on `dockerfile_result.changed`; tag as `bitsalt/{{ item.site_name }}-wordpress:{{ item.wp_image_revision | default(1) }}`; remove `build: .` from the compose template; replace `image: {{ item.site_name }}-wordpress` with the pinned-tag form. Compose v2 introspects pinned tags cleanly, so check-mode goes quiet and apply-time recreate is gated on actual image change.
- (b) and (c) remain rejected for the reasons given above. (b)'s sync hazard does not go away under fallback. (c)'s convergence-semantics break does not go away under fallback.
- This ADR would be rewritten under that fallback and re-circulated for approval before the Developer task lands.
