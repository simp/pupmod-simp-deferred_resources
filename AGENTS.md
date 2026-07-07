# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## What this module does

`pupmod-simp-deferred_resources` is a SIMP Puppet module that adds resources to
the Puppet catalog **after** the catalog has been compiled but **before** it is
applied. It is intended to help meet common policy requirements ("this package /
user / group / file must be present or absent") without conflicting with
resources that other modules have already declared: for each requested resource,
it checks whether that resource already exists in the compiled catalog and only
takes action when it does not.

The module is deliberately conservative. By default it runs in `warning` mode,
where it only logs what it *would* have done and never mutates the catalog. It
must be switched to `enforcing` mode to actually add (or override) resources.
Because it manipulates the catalog post-compilation, it is explicitly **not**
meant for general use — read the warnings in `manifests/init.pp` and
`lib/puppet/type/deferred_resources.rb` before extending it.

### Business logic

The real work happens in a custom Puppet **type** (not a provider); the
manifests are thin wrappers that translate Hiera-friendly parameters into
instances of that type.

- **`deferred_resources` type (`lib/puppet/type/deferred_resources.rb`)** — the
  engine. It is **not meant to be called directly**; use the helper classes.
  Its logic lives entirely inside an `autorequire(:file)` block, which Puppet
  evaluates after compilation. For each entry in `:resources` it:
  - Merges `:default_options` with the per-entry options and symbolises keys.
  - Looks up an existing resource via `catalog.resource(Type, name)`.
  - **If the resource already exists:**
    - With `:override_existing_attributes` set and `mode == :enforcing`, it
      mutates the existing catalog resource — setting the listed attributes and
      deleting any attributes named in that attribute's `invalidates` list
      (e.g. setting `content` invalidates `source`). This is effectively a
      controlled resource collector and is the dangerous path.
    - Without overrides, if the requested options match the existing resource it
      logs a debug "Ignoring existing resource"; if they differ it logs at
      `:log_level` that an existing resource has options that differ (a possible
      policy violation).
  - **If the resource does not exist:** in `enforcing` mode it calls
    `catalog.create_resource(Type, opts)`; in `warning` mode it logs "Would have
    created …" at `:log_level`.
  - Key params: `:name` (namevar), `:resource_type` (string, matched `/.+/`),
    `:resources` (Hash or Array — an Array is munged to a Hash of `{name => {}}`,
    and each entry gets its `name` key populated), `:default_options` (Hash),
    `:override_existing_attributes` (Hash/Array; only the `invalidates` control
    option is accepted, validated at parse time), `:log_level` (defaults
    `:warning`), and `:mode` (`:warning`/`:enforcing`, defaults `:warning`).
  - The `autorequire` block always returns `[]` — it uses the autorequire hook
    purely as a post-compile execution point and never actually declares an
    autorequire edge.

- **`deferred_resources` (`manifests/init.pp`)** — public entry class. Params:
  `$auto_include` (`Boolean`, default `true`) includes the four sub-classes;
  `$mode` (`Enum['warning','enforcing']`, default `'warning'`) and `$log_level`
  (`Simplib::PuppetLogLevel`, default `'info'`) are the module-wide defaults
  inherited by the sub-classes. Including the class is safe by default because
  the sub-classes do nothing until given resources and `mode` is `enforcing`.

- **`deferred_resources::packages` (`manifests/packages.pp`)** —
  `inherits deferred_resources`. Takes `$remove`/`$install` (`Variant[Hash,Array]`),
  `$remove_ensure` (`Enum['absent','purged']`), `$install_ensure`
  (`Enum['latest','present','installed']`), and `$default_options` (Hash). For a
  non-empty `$remove`/`$install` it declares a `deferred_resources{}` instance
  with `resource_type => 'package'`, merging `default_options` with the ensure
  value. `$install_ensure` is the **only** `simplib::lookup` seam in the module
  (see Gotchas).

- **`deferred_resources::files` (`manifests/files.pp`)** —
  `inherits deferred_resources`. Takes `$remove` (`Array[Stdlib::Absolutepath]`),
  `$install` (`Hash[Stdlib::Absolutepath, Hash]`), and
  `$update_existing_resources` (`Boolean`, default `false`). When
  `$update_existing_resources` is true it builds
  `$_override_existing_attributes = { owner => undef, group => undef, mode => undef,
  content => { invalidates => ['source'] } }` and passes it through to the install
  instance — this is the **DANGEROUS** path that edits resources already in the
  catalog. Remove uses `ensure => absent`, install uses `ensure => present`.

- **`deferred_resources::users` (`manifests/users.pp`)** and
  **`deferred_resources::groups` (`manifests/groups.pp`)** — nearly identical.
  Both `inherit deferred_resources`, take `$remove` (`Array[String[1]]`) and
  `$install` (`Variant[Hash, Array[String[1]]]`), and declare
  `deferred_resources{}` instances with `resource_type => 'user'`/`'group'`,
  `ensure => absent` for remove and `ensure => present` for install.

None of the sub-classes call `assert_private()`; they are documented as helpers
but are technically public. Ordering is implicit — everything is deferred to the
type's post-compile hook, so there are no explicit `require`/`notify` edges among
these resources.

### Gotchas / non-obvious details

- **`warning` is the default mode.** Nothing is added or changed until `$mode`
  is set to `enforcing`. In `warning` mode the module only logs. This is the
  single most surprising trait for someone expecting resources to appear.
- **`update_existing_resources` (files) mutates existing catalog resources.**
  It is the only path that changes resources declared by other modules, and
  setting `content` deletes `source` on the target via the `invalidates`
  mechanism. Treat it as a controlled resource collector; the module docs
  recommend a real Resource Collector instead when you want to be explicit.
- **The type does its work in an `autorequire(:file)` block.** This is a
  deliberate hack to run code post-compilation; it is not a real autorequire and
  always returns `[]`. Don't "fix" it into a normal autorequire.
- **`simp/simplib` is declared and IS used, but only in one place.** Metadata
  declares `simp/simplib`, and `manifests/packages.pp` uses exactly one
  `simplib::lookup` seam: `$install_ensure` defaults to
  `simplib::lookup('simp_options::package_ensure', { 'default_value' => 'installed' })`.
  No other manifest references `simp_options::*` or `simplib::lookup`; simplib is
  otherwise used only for the `Simplib::PuppetLogLevel` data type.
- **Array vs Hash resources are normalised in the type.** Passing an Array of
  names is munged into `{name => {}}`; each entry always gets a `name` key. The
  helper classes raise if the same item appears in both `remove` and `install`
  (documented behaviour; the collision surfaces as a duplicate-resource error).
- **`override_existing_attributes` validation is strict.** The only accepted
  control option is `invalidates`, and its value must be an Array; anything else
  raises at catalog compile time.
- **Deep-merge Hiera lookups.** `data/common.yaml` sets `lookup_options` so all
  `remove`/`install`/`default_options` parameters deep-merge across the
  hierarchy, with a `--` knockout prefix on the `install`/`default_options`
  keys. Contributions to these keys accumulate rather than replace.

## Dependencies

Module dependencies (from `metadata.json`):

- `simp/simplib` (`>= 4.9.0 < 5.0.0`) — provides `simplib::lookup` and the
  `Simplib::PuppetLogLevel` type.
- `puppetlabs/stdlib` (`>= 8.0.0 < 10.0.0`) — provides `Stdlib::Absolutepath`.

Fixture-only dependencies (from `.fixtures.yml`): `simplib` and `stdlib` are
pulled from their SIMP GitHub repos; the module itself is symlinked in.

Runtime requirement (from `metadata.json` `requirements`): `puppet >= 7.0.0 < 9.0.0`.
(SIMP is migrating Puppet → OpenVox; when `metadata.json` switches this to
`openvox`, update this line to match.)

Supported OS matrix (from `metadata.json`):

- Amazon 2
- CentOS 7, 8, 9
- RedHat 7, 8, 9
- OracleLinux 7, 8, 9
- Rocky 8, 9
- AlmaLinux 8, 9

## Repository layout

- `manifests/init.pp` — public class `deferred_resources` (mode/log_level defaults, auto-include).
- `manifests/packages.pp` / `users.pp` / `groups.pp` / `files.pp` — helper classes per resource type.
- `lib/puppet/type/deferred_resources.rb` — the custom type that does all the post-compile work.
- `types/` — present but empty (no custom Puppet data types defined here).
- `templates/` — present but empty.
- `data/common.yaml` + `hiera.yaml` — module Hiera data; `common.yaml` holds the deep-merge `lookup_options`.
- `spec/classes/` — rspec-puppet unit tests for each helper class.
- `spec/unit/puppet/type/deferred_resources_spec.rb` — unit tests for the custom type.
- `spec/acceptance/suites/default/` and `spec/acceptance/suites/compliance/` — beaker acceptance suites; `nodesets/` holds per-OS node definitions.
- `REFERENCE.md` — generated Puppet Strings reference (do not hand-edit; regenerate).
- `metadata.json` — module metadata, dependencies, supported OS matrix.
- `.github/workflows/pr_tests.yml` — PR CI.

**CI does not run acceptance/beaker.** `pr_tests.yml` runs syntax, lint,
rubocop, file-checks, RELENG checks, and `rake spec` (Puppet 7 and 8 matrix)
only. The beaker suites under `spec/acceptance/` must be run manually.

## Common commands

Rake tasks come from `Simp::Rake::Pupmod::Helpers` (see `Rakefile`). Gem pins of
note (from `Gemfile`): `puppetlabs_spec_helper ~> 8.0.0`,
`simp-rake-helpers ~> 5.24.0`, `simp-beaker-helpers ~> 2.0.0`.

```sh
bundle install

# Unit tests (rspec-puppet + type unit tests)
bundle exec rake spec

# Run a single spec file
bundle exec rspec spec/unit/puppet/type/deferred_resources_spec.rb

# Lint / style
bundle exec rake lint
bundle exec rake rubocop

# Regenerate REFERENCE.md after changing manifest docstrings
bundle exec puppet strings generate --format markdown --out REFERENCE.md

# Acceptance tests (beaker; needs a hypervisor — NOT run in CI)
bundle exec rake beaker:suites[default]
```

Note `.rspec` sets `--fail-fast`, so `rake spec` stops at the first failure.

## Conventions

- This is a component of the SIMP ecosystem. Follow SIMP module conventions.
- The safety posture is the whole point: `warning` mode must stay the default,
  and any new resource type must keep the "only act on resources not already in
  the catalog" contract. Do not make the module clobber existing resources
  except through the explicit `override_existing_attributes` path.
- The custom type is the load-bearing code. Keep its post-compile
  (`autorequire`) execution model, its Array→Hash munging, and its strict
  `override_existing_attributes` validation intact when editing.
- Keep manifest parameter `@param` docstrings and the type's `desc` strings
  current — `REFERENCE.md` is generated from them.
