# This class takes two `Hashes` of group resources, one to remove, and one to
# install.
#
# After the entire puppet catalog has been compiled, it will process both lists
# and, for any resource that is not already defined in the catalog, it will
# take the appropriate action.
#
# An exception will be raised if you list the same group in both lists.
#
# @param $remove
#   A list of groups to remove.
#
# @param $install
#   A list of groups to install.
#
#   * A `Hash` can be used to add extra attributes for the group, but the
#     `ensure` attribute will always be set to `absent` for removal and
#     `present` for creation.
#
# @param $mode
#   @see `deferred_resources::mode`
#
# @param $log_level
#   @see `deferred_resources::log_level`
#
class deferred_resources::groups (
  Variant[Array[String[1]]]       $remove    = [],
  Variant[Hash, Array[String[1]]] $install   = {},
  Enum['warning','enforcing']     $mode      = $deferred_resources::mode,
  Simplib::PuppetLogLevel         $log_level = $deferred_resources::log_level

) inherits deferred_resources {

  unless empty($remove) {
    deferred_resources{ "${module_name} Group remove":
      resources       => $remove,
      resource_type   => 'group',
      default_options => { 'ensure' => 'absent' },
      mode            => $mode,
      log_level       => $log_level
    }
  }

  unless empty($install) {
    deferred_resources{ "${module_name} Group install":
      resources       => $install,
      resource_type   => 'group',
      default_options => { 'ensure' => 'present' },
      mode            => $mode,
      log_level       => $log_level
    }
  }
}
