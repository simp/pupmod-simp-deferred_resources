# This class takes two `Hashes` of user resources, one to remove, and one to
# install.
#
# After the entire puppet catalog has been compiled, it will process both lists
# and, for any resource that is not already defined in the catalog, it will
# take the appropriate action.
#
# An exception will be raised if you list the same user in both lists.
#
# @param $remove
#   A list of users to remove.
#
#   * A `Hash` can be used to add extra attributes for the user, but the
#     `ensure` attribute will be overwritten if it is included.
#
# @param $install
#   A list of users to install.
#
#   * A `Hash` can be used to add extra attributes for the user, but the
#     `ensure` attribute will always be set to `$user_ensure`.
#
# @param $default_options
#   A `Hash` of options to apply to all users (both remove and install.
#   If ensure is entered in these options it will be overwritten.
#
#   * These options may be anything that a Puppet `User` resource can
#     normally accept.
#
# @param $mode
#   @see `deferred_resources::mode`
#
# @param $log_level
#   @see `deferred_resources::log_level`
#
class deferred_resources::users (
  Variant[Hash, Array[String[1]]]      $remove          = {},
  Variant[Hash, Array[String[1]]]      $install         = {},
  Hash                                 $default_options = {},
  Enum['warning','enforcing']          $mode            = $deferred_resources::mode,
  Simplib::PuppetLogLevel              $log_level       = $deferred_resources::log_level

) inherits deferred_resources {

  unless empty($remove) {
    deferred_resources{ "${module_name} User remove":
      resources       => $remove,
      resource_type   => 'user',
      default_options => $default_options + { 'ensure' => 'absent' },
      mode            => $mode,
      log_level       => $log_level
    }
  }

  unless empty($install) {
    deferred_resources{ "${module_name} User install":
      resources       => $install,
      resource_type   => 'user',
      default_options => $default_options + { 'ensure' => 'present' },
      mode            => $mode,
      log_level       => $log_level
    }
  }
}
