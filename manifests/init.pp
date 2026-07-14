# **WARNING:** This module is intended to help meet common policy requirements
# for resources being either present or absent on a system and is not meant
# for general usage. Make sure you understand the ramifications of what this
# module does to the Puppet catalog prior to using it outside of the SIMP
# framework.
#
# This class takes a Hash of resources, keyed by resource type. After the
# entire puppet catalog has been compiled, any listed resource that is not
# already declared in the catalog will be added to the catalog.
#
# Resources that already exist in the catalog are never touched unless an
# entry sets the reserved `override` option to `true`, in which case only the
# attributes specified on that entry will be updated on the existing resource.
#
# @param resources
#   A Hash of resources, keyed by resource type, to process after the catalog
#   has been compiled
#
#   * Any native resource type may be used and any mix of resource types may
#     be passed in the same Hash
#   * Each entry is a Hash of resource titles to (optional) resource
#     attributes, exactly as you would declare the resource normally
#   * The `override` attribute name is **reserved** as a control option and is
#     never passed to the underlying resource:
#
#     **DANGEROUS** - READ CAREFULLY
#
#     Setting `override: true` on an entry will force all of the attributes
#     specified on that entry onto a matching resource that **already exists**
#     in the catalog. An attribute explicitly set to `undef` (`~` in YAML)
#     will be *removed* from the existing resource (e.g. unsetting `source`
#     when specifying `content`). This is basically a controlled resource
#     collector and absolutely must not be taken lightly when used since it
#     will affect existing resources in your catalog. If you want to be
#     explicit, use a Resource Collector and do not set this.
#
#   @example Ensure packages and users using Hieradata, overriding one file
#     deferred_resources::resources:
#       package:
#         telnet:
#           ensure: 'absent'
#         tmpwatch:
#           ensure: 'installed'
#       user:
#         ftp:
#           ensure: 'absent'
#       file:
#         /etc/motd:
#           ensure: 'file'
#           content: 'Authorized use only'
#           source: ~
#           override: true
#
# @param default_options
#   A Hash of attributes, keyed by resource type, that will be applied to
#   every resource of that type in `$resources`
#
#   * Attributes set directly on an entry in `$resources` take precedence
#   * May include `override` to set the default override behavior for every
#     resource of a type
#
# @param mode
#   If set to `enforcing` then this class will take action on the system. If
#   set to `warning` a message will be printed noting what would have taken
#   place on the system but the catalog will not be updated.
#
# @param log_level
#   Set the log level for warning messages
#
class deferred_resources (
  Hash[String[1], Hash[String[1], Optional[Hash]]] $resources       = {},
  Hash[String[1], Hash]                            $default_options = {},
  Enum['warning','enforcing']                      $mode            = 'warning',
  Simplib::PuppetLogLevel                          $log_level       = 'info'
) {
  # Normalize the resource type names so that variants of the same type (e.g.
  # 'Package' and 'package') cannot result in duplicate resource declarations
  # below
  $_resources = $resources.reduce({}) |$memo, $kv| {
    $_type = downcase($kv[0])

    if $_type in $memo {
      fail("deferred_resources: Resource type '${_type}' was passed to \$resources more than once (type names are case-insensitive)")
    }

    $memo + { $_type => $kv[1] }
  }

  $_default_options = Hash($default_options.map |$k, $v| { [downcase($k), $v] })

  # The native type would only be able to report a bad control option at
  # apply time, so catch it at compile time instead
  $_default_options.each |$_type, $_opts| {
    if ('override' in $_opts) and !($_opts['override'] =~ Boolean) {
      fail("deferred_resources: The 'override' option in \$default_options for resource type '${_type}' must be a Boolean")
    }
  }

  $_resources.each |$_type, $_entries| {
    unless empty($_entries) {
      # The native type would only be able to report a bad control option at
      # apply time, so catch it at compile time instead
      $_entries.each |$_title, $_opts| {
        if ($_opts =~ Hash) and ('override' in $_opts) and !($_opts['override'] =~ Boolean) {
          fail("deferred_resources: The 'override' option on ${_type} resource '${_title}' must be a Boolean")
        }
      }

      # Detect entries that reference the same underlying resource through an
      # explicit 'name' attribute so that processing cannot become order
      # dependent
      $_names = $_entries.map |$_title, $_opts| {
        $_opts ? {
          Hash    => pick($_opts['name'], $_title),
          default => $_title,
        }
      }

      unless $_names.length == $_names.unique.length {
        $_duplicates = $_names.unique.filter |$_name| {
          $_names.filter |$_candidate| { $_candidate == $_name }.length > 1
        }

        $_duplicate_list = join($_duplicates, "', '")
        fail("deferred_resources: The following ${_type} resources were specified multiple times via their title or 'name' attribute: '${_duplicate_list}'")
      }

      deferred_resources { "${module_name} ${_type}":
        resources       => $_entries,
        resource_type   => $_type,
        default_options => pick($_default_options[$_type], {}),
        mode            => $mode,
        log_level       => $log_level,
      }
    }
  }
}
