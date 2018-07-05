**FIXME**: Ensure the badges are correct and complete, then remove this message!

[![License](http://img.shields.io/:license-apache-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0.html) [![Build Status](https://travis-ci.org/simp/pupmod-simp-deferred_resources.svg)](https://travis-ci.org/simp/pupmod-simp-deferred_resources) [![SIMP compatibility](https://img.shields.io/badge/SIMP%20compatibility-6.*-orange.svg)](https://img.shields.io/badge/SIMP%20compatibility-6.*-orange.svg)

#### Table of Contents

1. [Description](#description)
2. [Setup - The basics of getting started with deferred_resources](#setup)
    * [What deferred_resources affects](#what-deferred_resources-affects)
    * [Setup requirements](#setup-requirements)
    * [Beginning with deferred_resources](#beginning-with-deferred_resources)
3. [Usage - Configuration options and additional functionality](#usage)
4. [Reference - An under-the-hood peek at what the module is doing and how](#reference)
5. [Limitations - OS compatibility, etc.](#limitations)
6. [Development - Guide for contributing to the module](#development)
    * [Acceptance Tests - Beaker env variables](#acceptance-tests)

## Description

This module provides custom types to add resources to the catalog after all manifests have been compiled.  It is not recommended for general use.  It was developed for a specific circumstance where the STIG required packages to be installed.  In order to not interfer with other manifests that might have included resources, it first checks if the resource has been included in the catalog and creates it.  

### This is a SIMP module

This module is a component of the [System Integrity Management
Platform](https://github.com/NationalSecurityAgency/SIMP), a
compliance-management framework built on Puppet.

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

## Setup

## Usage

This module provide a type deferred_packages

   deferred_packages { 'my_packages':
      package_list => $my package_list',
      default_attr => $my_default_attr,
      mode         => $my_mode,
   }

package_list  is a list of packages to install. It can be either a Hash of the form:
     'Package Name' => { Hash of Attirbutes }
     an array of names of packages.  If it is an Array then the default attributes
     must not be entry.
default_attr  is a Hash of attributes to apply to all packages in the list.

mode is either 
     'warning' - The package will not be added to the catalog but a warning
          will be printed out to indicate it is missing.
     'enforcing' - A package resource will be added to the catalog for the package.
EXAMPLE #1:
$package_list = ['rsh','rsh-server',ypserv']
$default_attr = {'ensure' => 'absent'}

deffered_packages { 'STIG_PACKAGES':
    package_list => $package_list,
    default_attr => $default_attr,
    mode         => 'enforcing'
}

EXAMPLE #2

$package_list = {
  'ypserv' => {'ensure' => 'absent'},
  'screen' => {'ensure' => 'presnet'}
}

deferred_pacakges { 'STIG_PACKAGES':
   package_list => $package_list,
   mode         => 'warning'
}

## Reference


Please refer to the inline documentation within each source file, or to the
module's generated YARD documentation for reference material.

## Limitations

SIMP Puppet modules are generally intended for use on Red Hat Enterprise Linux
and compatible distributions, such as CentOS. Please see the
[`metadata.json` file](./metadata.json) for the most up-to-date list of
supported operating systems, Puppet versions, and module dependencies.

## Development


Please read our [Contribution Guide](http://simp-doc.readthedocs.io/en/stable/contributors_guide/index.html).

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
