# This class takes an Array of file resources to remove, and a Hash of file
# resources to install.
#
# After the entire puppet catalog has been compiled, it will process both lists
# and, for any resource that is not already defined in the catalog, it will
# take the appropriate action.
#
# An exception will be raised if you list the same file in both lists.
#
# @param remove
#   A list of files to remove.
#
# @param install
#   A Hash of files to install.
#
# @param update_existing_resources
#   **DANGEROUS** - READ CAREFULLY
#
#   Update the following attributes of resources that already exist in the
#   catalog if set in the `install` Hash:
#
#     * user
#     * group
#     * content
#       * Will unset `source`
#
#   If you wish to affect additional parameters on an existing resource in the
#   catalog, you should not use this class and should instead use a Resource
#   Collector.
#
#   @see https://puppet.com/docs/puppet/5.3/lang_resources_advanced.html#amending-attributes-with-a-collector
#
# @param mode
#   @see `deferred_resources::mode`
#
# @param log_level
#   @see `deferred_resources::log_level`
#
class deferred_resources::files (
  Array[Stdlib::Absolutepath]      $remove                    = [],
  Hash[Stdlib::Absolutepath, Hash] $install                   = {},
  Boolean                          $update_existing_resources = false,
  Enum['warning','enforcing']      $mode                      = $deferred_resources::mode,
  Simplib::PuppetLogLevel          $log_level                 = $deferred_resources::log_level

) inherits deferred_resources {

  if $update_existing_resources {
    $_override_existing_attributes = {
      'owner'   => undef,
      'group'   => undef,
      'mode'    => undef,
      'content' => {
        'invalidates' => ['source']
      }
    }
  }
  else {
    $_override_existing_attributes = undef
  }

  unless empty($remove) {
    deferred_resources{ "${module_name} File remove":
      resources                    => $remove,
      resource_type                => 'file',
      default_options              => { 'ensure' => 'absent' },
      mode                         => $mode,
      log_level                    => $log_level
    }
  }

  unless empty($install) {
    deferred_resources{ "${module_name} File install":
      resources                    => $install,
      resource_type                => 'file',
      default_options              => { 'ensure' => 'present' },
      override_existing_attributes => $_override_existing_attributes,
      mode                         => $mode,
      log_level                    => $log_level
    }
  }
}
