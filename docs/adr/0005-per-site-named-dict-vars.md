# ADR 0005: Per-site var file using the named-dict pattern

**Status:** accepted
**Date:** 2026-04-24

## Context

Each site has 10–20 configuration values: domain, image tag, DB connection details, table prefix (WordPress), env vars (webapp), feature flags (`enabled`, queue worker, scheduler cron). These values are loop-input for the `wordpress`, `laravel`, and `webapp` roles. Adding a new site should be one well-defined edit — not multiple coordinated changes across files.

## Decision

**Each site has its own var file** at `playbooks/vars/sites/<site>.yml`, defining a **named dict** for that site (e.g., `taotedev_site: {...}`). The site dicts are loaded via `vars_files` and assembled into per-stack lists in `site.yml`:

```yaml
# site.yml
vars_files:
  - vars/sites/taotedev.yml
  - vars/sites/bitsalt.yml
  # ...

vars:
  wordpress_sites:
    - "{{ taotedev_site }}"
    - "{{ bitsalt_site }}"
    # ...

tasks:
  - name: WordPress sites
    ansible.builtin.include_role:
      name: wordpress
      apply: { tags: [wordpress] }
    loop: "{{ wordpress_sites }}"
    loop_control: { loop_var: item }
```

Each site dict carries an `enabled` flag; sites with `enabled: false` are skipped without their var file being removed.

## Consequences

**Easier:**
- Adding a site = one new var file + one new line in `site.yml` + one vault entry. No edits to roles or shared vars.
- Each site's full config is visible in one place (`vars/sites/<site>.yml`).
- Per-stack lists in `site.yml` make the active fleet observable at a glance.
- `enabled: false` is a one-line "park this site" mechanism.

**Harder:**
- The named-dict-per-file pattern is non-obvious to a new operator; the role-loop wiring in `site.yml` must be understood. Mitigated by the role argument-spec validation (Ansible addendum §5/§14), which fails fast with a clear error when a required field is missing.
- Cross-site shared values (e.g., a default WP image tag) need a separate global home — currently `wordpress_default_image` in `group_vars/all/vars.yml`. Sites that override it pin their own `wp_image` value.
- Per-site var files duplicate boilerplate fields. Acceptable tax; a template file (`vars/sites/_template-wordpress.yml`) could reduce friction further if needed.

**Reconsider if:**
- The fleet grows beyond ~30 sites and the per-site overhead of 8 active site files becomes a real maintenance cost.
- A use case appears that needs runtime composition of site dicts (e.g., from an external inventory) rather than committed files.

## Alternatives considered

- **Flat per-site var files** (`taotedev_db_password`, `taotedev_domain`, `taotedev_image`...). Rejected: every var ends up in a single namespace; risk of silent collision; harder to spot a site's complete config; awkward to loop over.
- **Sites in `group_vars/`.** Rejected: `group_vars` is for *groups* of hosts, not for fleet inventory. Misuses the directory's intent.
- **All sites inline in `site.yml`.** Rejected: doesn't scale; one editor can't easily own a site's lifecycle without merge conflicts; loses the per-site file boundary.
- **External inventory (e.g., generated from a database).** Rejected today: adds a runtime dependency the project doesn't need; reconsider if fleet size or dynamic behavior warrants.
