# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## What this module does

`pupmod-simp-deferred_resources` is a SIMP Puppet module that adds resources to
the Puppet catalog **after** the catalog has been compiled but **before** it is
applied. It is intended to help meet common policy requirements ("this package /
user / group / file must be present or absent") without conflicting with
resources that other modules have already declared: for each requested resource,
it checks whether that resource already exists in the compiled catalog and only
takes action when it does not (unless a specific entry opts into overriding).

The module is deliberately conservative. By default it runs in `warning` mode,
where it only logs what it *would* have done and never mutates the catalog. It
must be switched to `enforcing` mode to actually add (or override) resources.
Because it manipulates the catalog post-compilation, it is explicitly **not**
meant for general use — read the warnings in `manifests/init.pp` and
`lib/puppet/type/deferred_resources.rb` before extending it.

## Architecture

Two layers: a custom Puppet **type** that does all the real work, and a single
public wrapper **class** that translates a Hiera-friendly Hash into instances
of that type. (Before 2.0.0 there were four per-type helper classes —
`::packages`, `::users`, `::groups`, `::files` — with `remove`/`install`
lists; they no longer exist.)

### `deferred_resources` type (`lib/puppet/type/deferred_resources.rb`)

The engine. It is **not meant to be declared directly**; use the class. Its
logic lives entirely inside an `autorequire(:file)` block, which Puppet
evaluates on the agent after compilation but before application — the only
window where the full catalog can be inspected and injected into. The block
always returns `[]`; it is not a real autorequire and declares no dependency
edges. Don't "fix" it into a normal autorequire.

Processing per run:

- Resolves the RAL class for `:resource_type`; an unknown type logs at
  `:log_level` and skips all entries rather than failing the catalog run.
- For isomorphic types, builds a namevar => resource map of the catalog once
  per run. Catalog aliases are stored by composite uniqueness key (e.g.
  `[provider, name]` for packages), so a resource managing the same underlying
  entity under a different title cannot be found by a title lookup and would
  otherwise raise a duplicate resource/alias error at creation time.
- For each entry in `:resources`: merges `:default_options` under the entry's
  options, symbolizes keys, and pops the reserved `override` control option.
  Existing resources are found by title, then by explicit `name`, then via the
  namevar map.
  - **Resource exists, entry has `override: true`:** in `enforcing` mode every
    attribute specified on the entry is forced onto the existing resource, and
    an attribute explicitly set to `nil`/undef is **deleted** from it (e.g.
    unsetting `source` when setting `content`); in `warning` mode it logs
    "Would have overridden…". This is the dangerous, resource-collector-like
    path.
  - **Resource exists, no override:** identical options log a debug "Ignoring
    existing resource"; differing options log at `:log_level` (a potential
    policy violation). The existing resource always wins.
  - **Resource missing:** `enforcing` calls `catalog.create_resource`
    (nil-valued attributes are stripped); `warning` logs "Would have created…".
- Key params: `:name` (namevar), `:resource_type` (String), `:resources`
  (Hash or Array — an Array is munged to `{name => {}}` and every entry gets a
  `name` key populated), `:default_options` (Hash), `:log_level` (defaults
  `:warning`), `:mode` (`:warning`/`:enforcing`, defaults `:warning`). A
  non-Boolean `override` value on an entry is rejected at validation.

### `deferred_resources` class (`manifests/init.pp`)

The only public entry point. Parameters:

- `$resources` — `Hash[String[1], Hash[String[1], Optional[Hash]]]`, keyed by
  resource type, e.g.
  `{'package' => {'telnet' => {'ensure' => 'absent'}}, 'user' => {...}}`. Any
  native type and any mix of types is accepted; one `deferred_resources` type
  instance is declared per resource type.
- `$default_options` — Hash keyed by resource type, applied under every entry
  of that type (may include `override` to default it type-wide; entries can
  opt back out with `override => false`).
- `$mode` (`Enum['warning','enforcing']`, default `'warning'`) and
  `$log_level` (`Simplib::PuppetLogLevel`, default `'info'`; the *type's* own
  default is `:warning`, so the effective level via the class is `info`).

The class fails at **compile time** (rather than nondeterministically at apply
time) when:

- the same resource type appears twice in `$resources` after case
  normalization (`package` + `Package`);
- two entries of a type reference the same underlying resource via their title
  or an explicit `name` attribute;
- an entry's `override` option is not a Boolean.

## Gotchas / non-obvious details

- **`warning` is the default mode.** Nothing is added or changed until `$mode`
  is `enforcing`; the module only logs. This is the single most surprising
  trait for someone expecting resources to appear.
- **`override` is a reserved attribute name.** It is popped from the entry's
  options and never reaches the real resource, so a resource attribute
  literally named `override` cannot be managed through this module.
- **Overrides enforce exactly what the entry specifies.** There is no
  per-attribute allow-list; every attribute on an overriding entry is applied,
  and explicit undef (`~` in YAML) removes the attribute from the existing
  resource. This replaced the pre-2.0.0
  `update_existing_resources`/`override_existing_attributes`/`invalidates`
  mechanism.
- **Deep-merge Hiera lookups.** `data/common.yaml` sets `lookup_options` with
  deep merge and a `--` knockout prefix for `deferred_resources::resources`
  and `deferred_resources::default_options`; SIMP stack data is expected to
  merge into these hashes.
- **simplib is only used for the `Simplib::PuppetLogLevel` data type.** The
  pre-2.0.0 `simplib::lookup('simp_options::package_ensure', ...)` seam was
  removed with the packages class.

## Dependencies and support

- `simp/simplib` and `puppetlabs/stdlib` (see `metadata.json` for ranges).
- Runtime requirement: `openvox >= 8.0.0 < 9.0.0`.
- Supported OSes: EL8/9/10 family (CentOS, RedHat, OracleLinux, Rocky,
  AlmaLinux) per `metadata.json`.
- Fixtures (`.fixtures.yml`): `simplib` and `stdlib` clone from GitHub;
  `puppet_fixtures` symlinks the module itself automatically.

## Repository layout

- `manifests/init.pp` — the single public class.
- `lib/puppet/type/deferred_resources.rb` — the custom type that does all the post-compile work.
- `data/common.yaml` + `hiera.yaml` — module Hiera data (deep-merge `lookup_options`).
- `spec/classes/init_spec.rb` — rspec-puppet tests for the class (including the compile-time failure modes).
- `spec/unit/puppet/type/deferred_resources_spec.rb` — unit tests for the type (including override, namevar-collision, and unknown-type behavior).
- `spec/acceptance/suites/default/` — Beaker: mixed-type warning/enforcing flow and per-resource override suites.
- `spec/acceptance/suites/compliance/` — Beaker: STIG-like enforcement expressed through the module's own Hiera API (no `compliance_markup` dependency).
- `REFERENCE.md` — generated by openvox-strings (`rake strings:generate:reference`); do not hand-edit.
- `types/` and `templates/` — present but empty.

## Common commands

Rake tasks come from `simp-rake-helpers` (see `Rakefile`); run
`bundle exec rake -T` for the full list. The test toolchain is OpenVox-based
(`voxpupuli-test` provides the spec_helper and manages the rubocop pins).

```sh
bundle install                        # first-time setup
bundle exec rake spec                 # unit tests (spec_prep clones fixtures; spec cleans them afterwards)
bundle exec rake spec_prep            # re-clone fixtures (needed before running rspec directly)
bundle exec rspec spec/classes/init_spec.rb              # single spec file
bundle exec rspec spec/unit/puppet/type/deferred_resources_spec.rb  # type unit tests
bundle exec rake validate             # puppet parser validation
bundle exec rake lint                 # puppet-lint (config in .puppet-lint.rc)
bundle exec rake metadata_lint        # metadata.json lint
bundle exec rake rubocop              # Ruby style (lib/, spec/)
```

Acceptance tests (Beaker; Vagrant/VirtualBox by default, Docker nodesets
available):

```sh
bundle exec rake beaker:suites                          # all suites, default nodeset
bundle exec rake beaker:suites[default,docker_rocky9]   # one suite on a docker nodeset
BEAKER_destroy=no bundle exec rake beaker:suites        # keep VMs for debugging
```

CI (`.github/workflows/pr_tests.yml`) runs syntax/lint/rubocop/spec on OpenVox
8 (Ruby 3.2 and 3.4) plus an OpenVox 9 / Ruby 4.0 preview, and runs the
**default** beaker suite on docker nodesets; the `compliance` suite must be
run manually.

## Conventions

- `Gemfile`, `spec/spec_helper.rb`, `.gitignore`, and `.github/workflows/` are
  marked **maintained with puppetsync** — local edits will be overwritten by
  the next baseline sync; don't fix things there.
- Unit tests use `simp-rspec-puppet-facts` (`on_supported_os`) and iterate
  over the OSes in `metadata.json`.
- Tests and examples rely on nothing being changed on a system unless
  `enforcing` is explicit.
- In rspec-puppet params, use `:undef` (not Ruby `nil`) for undef values;
  catalog matchers see the type's munged values (entries gain `name`, nil
  options become `{}`).
