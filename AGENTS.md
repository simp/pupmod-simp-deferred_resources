# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## What this module is

`simp-deferred_resources` is a SIMP Puppet module that adds resources to the catalog **after** compilation but **before** application. It exists to satisfy compliance policies (DISA STIG, CIS) that require packages/users/groups/files to be present or absent, without clobbering resources other manifests already manage. It is not intended for general use outside the SIMP framework.

## Commands

Rake tasks come from `simp-rake-helpers` (see `Rakefile`); run `bundle exec rake -T` for the full list.

```bash
bundle install                        # first-time setup
bundle exec rake spec                 # unit tests (clones fixtures from .fixtures.yml on first run)
bundle exec rspec spec/classes/init_spec.rb              # single spec file
bundle exec rspec spec/unit/puppet/type/deferred_resources_spec.rb  # type unit tests
bundle exec rake validate             # puppet parser validation
bundle exec rake lint                 # puppet-lint (config in .puppet-lint.rc)
bundle exec rake metadata_lint        # metadata.json lint
bundle exec rubocop                   # Ruby style (lib/, spec/)
```

Acceptance tests (Beaker; Vagrant/VirtualBox by default, Docker nodesets available):

```bash
bundle exec rake beaker:suites                       # all suites, default nodeset
bundle exec rake beaker:suites[default,docker_rocky9]  # one suite on a docker nodeset
BEAKER_destroy=no bundle exec rake beaker:suites     # keep VMs for debugging
```

Suites live in `spec/acceptance/suites/` (`default`, `compliance`); nodesets in `spec/acceptance/nodesets/`.

## Architecture

Two layers:

1. **Custom type** — `lib/puppet/type/deferred_resources.rb`. All real logic lives here, inside an `autorequire(:file)` block. This is deliberate: autorequire hooks run on the agent after the catalog is compiled but before it is applied, which is the only window where the type can inspect the full catalog and inject resources. The block always returns `[]` — it creates no actual dependencies. For each entry in `:resources` it:
   - skips (debug log) if an identical resource is already in the catalog;
   - logs at `:log_level` if an existing resource has *different* options (potential policy violation);
   - in `enforcing` mode, calls `catalog.create_resource` for missing resources; in `warning` mode (the default everywhere) it only logs what it *would* do;
   - optionally mutates existing resources when an entry sets the reserved `override: true` control option (a controlled resource-collector substitute): every attribute on the entry is forced onto the existing resource, and an attribute explicitly set to undef/`~` is removed from it (e.g. unsetting `source` when setting `content`). `override` is popped from the options and never reaches the real resource.

2. **The single wrapper class** — `manifests/init.pp`. Users are meant to use this, never the type directly. `deferred_resources` accepts a `resources` Hash keyed by resource type (`{'package' => {'telnet' => {'ensure' => 'absent'}}, 'user' => {...}}`) plus a per-type `default_options` Hash, and declares one `deferred_resources` type instance per resource type. It normalizes type-name case (failing on duplicates like `package` + `Package`), fails at compile time when two entries reference the same underlying resource via title or an explicit `name` attribute — otherwise apply-time processing would be order-dependent — and fails at compile time when an entry's `override` option is not a Boolean.

`data/common.yaml` sets deep-merge `lookup_options` with a `--` knockout prefix for `resources` and `default_options` — Hiera data across the SIMP stack is expected to merge into these hashes.

## Conventions

- `Gemfile`, `spec/spec_helper.rb`, and `.github/workflows/` are marked **maintained with puppetsync** — local edits will be overwritten by the next baseline sync; don't fix things there.
- Unit tests use `simp-rspec-puppet-facts` (`on_supported_os`) and iterate over the OSes in `metadata.json` (EL8/9/10 family only).
- The type's default mode is `warning`; tests and examples rely on nothing being changed on a system unless `enforcing` is explicit.
