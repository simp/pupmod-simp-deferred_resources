[![License](https://img.shields.io/:license-apache-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0.html)
[![CII Best Practices](https://bestpractices.coreinfrastructure.org/projects/73/badge)](https://bestpractices.coreinfrastructure.org/projects/73)
[![Puppet Forge](https://img.shields.io/puppetforge/v/simp/deferred_resources.svg)](https://forge.puppetlabs.com/simp/deferred_resources)
[![Puppet Forge Downloads](https://img.shields.io/puppetforge/dt/simp/deferred_resources.svg)](https://forge.puppetlabs.com/simp/deferred_resources)
[![Build Status](https://travis-ci.org/simp/pupmod-simp-deferred_resources.svg)](https://travis-ci.org/simp/pupmod-simp-deferred_resources)

#### Table of Contents

<!-- vim-markdown-toc GFM -->

* [Description](#description)
  * [This is a SIMP module](#this-is-a-simp-module)
* [Usage](#usage)
  * [Example: Managing a mix of resources](#example-managing-a-mix-of-resources)
  * [Example: The same configuration via Hiera, silencing messages](#example-the-same-configuration-via-hiera-silencing-messages)
  * [Example: Overriding attributes on existing catalog resources](#example-overriding-attributes-on-existing-catalog-resources)
* [Reference](#reference)
* [Limitations](#limitations)
* [Development](#development)
  * [Acceptance tests](#acceptance-tests)

<!-- vim-markdown-toc -->

## Description

This module provides capabilities to add resources to the puppet catalog
**after** the initial compilation has been compiled.

> **WARNING:**
>
> This module is not recommended for use outside of the SIMP
> framework. It was developed for specific policy requirements from the DISA
> STIG, CIS Benchmark, etc... that require resources to either be installed or
> removed.  In order to not interfere with other manifests that might have
> legitimately added resources, it first checks if each resource has already
> been included in the catalog and then adds the appropriate resource to add or
> remove that resource, as necessary.
>
> **WARNING:**

See [REFERENCE.md](./REFERENCE.md) for full API details.

### This is a SIMP module

This module is a component of the [System Integrity Management Platform](https://simp-project.com),
a compliance-management framework built on Puppet.

If you find any issues, they may be submitted to our [bug
tracker](https://simp-project.atlassian.net/).


This module is optimally designed for use within a larger SIMP ecosystem, but
it can be used independently:

 * When included within the SIMP ecosystem, security compliance settings will
   be managed from the Puppet server.
 * If used independently, all SIMP-managed security subsystems are disabled by
   default and must be explicitly opted into by administrators.  Please review
   the parameters in
   [`simp/simp_options`](https://github.com/simp/pupmod-simp-simp_options) for
   details.

## Usage

This module provides a single class, `deferred_resources`, that helps users
properly use the underlying native type for processing deferred resources. It
accepts a Hash of resources, keyed by resource type, and does not care which
resource types are passed to it.

Resources that already exist in the catalog are never touched unless an entry
sets the reserved `override` option to `true`, in which case only the
attributes specified on that entry are updated on the existing resource.

### Example: Managing a mix of resources

```
  class { 'deferred_resources':
    'resources' => {
      'package' => {
        'pkg1' => { 'ensure' => 'absent' },
        'pkg2' => { 'ensure' => 'absent' },
        'pkg3' => { 'ensure' => 'installed' },
      },
      'user' => {
        'baduser' => { 'ensure' => 'absent' },
      },
    },
    'mode'      => 'enforcing'
  }
```

### Example: The same configuration via Hiera, silencing messages

```yaml
deferred_resources::mode: 'enforcing'
deferred_resources::log_level: 'debug'
deferred_resources::resources:
  package:
    pkg1:
      ensure: 'absent'
    pkg2:
      ensure: 'absent'
    pkg3:
      ensure: 'installed'
  user:
    baduser:
      ensure: 'absent'
```

### Example: Overriding attributes on existing catalog resources

**WARNING:** This is effectively a controlled resource collector — make sure
you understand the ramifications before using it.

Setting `override: true` on an entry forces all of the attributes specified on
that entry onto a matching resource that already exists in the catalog. An
attribute explicitly set to `~` (undef) is *removed* from the existing
resource — here, `source` is unset so it cannot conflict with the new
`content`. The `override` key is reserved and is never passed to the resource.

```yaml
deferred_resources::mode: 'enforcing'
deferred_resources::resources:
  file:
    /etc/motd:
      ensure: 'file'
      owner: 'root'
      content: 'Authorized use only'
      source: ~
      override: true
```

## Reference

Please refer to the inline documentation within each source file, or to the
module's generated YARD documentation for reference material.

## Limitations

SIMP Puppet modules are generally intended for use on Red Hat Enterprise Linux
and compatible distributions, such as CentOS. Please see the
[`metadata.json` file](./metadata.json) for the most up-to-date list of
supported operating systems, Puppet versions, and module dependencies.

## Development


Please read our [Contribution Guide](https://simpdoc.readthedocs.io/en/stable/contributors_guide/index.html).

### Acceptance tests

This module includes [Beaker](https://github.com/puppetlabs/beaker) acceptance
tests using the SIMP [Beaker Helpers](https://github.com/simp/rubygem-simp-beaker-helpers).
By default the tests use [Vagrant](https://www.vagrantup.com/) with
[VirtualBox](https://www.virtualbox.org) as a back-end; Vagrant and VirtualBox
must both be installed to run these tests without modification. To execute the
tests run the following:

```shell
bundle install
bundle exec rake beaker:suites
```


Please refer to the [SIMP Beaker Helpers documentation](https://github.com/simp/rubygem-simp-beaker-helpers/blob/master/README.md)
for more information.
