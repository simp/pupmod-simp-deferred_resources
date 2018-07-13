# This class takes two `Hashes` of packages, one to remove and one to install.
#
# After the entire puppet catalog has been compiled, it will process both lists
# and, for any resource that is not already defined in the catalog, it will
# take the appropriate action.
#
# An exception will be raised if you list the same package in both lists.
#
# @param $remove
#   A list of packages to remove.
#
#   * A `Hash` can be used to add extra attributes for the package, but the
#     `ensure` attribute will be overwritten if it is included.
#
# @param $install
#   A list of packages to install.
#
#   * A `Hash` can be used to add extra attributes for the package, but the
#     `ensure` attribute will always be set to `$package_ensure`.
#
# @param $install_ensure
#   If installing, then this is the state that the packages should have.
#
#   * This will be overridden by anything set in options applied to an entry in
#     the `$install` Hash.
#
# @param $default_options
#   A `Hash` of options to apply to all packages (both remove and install.
#   If ensure is entered in these options it will be overwritten.
#
#   * These options may be anything that a Puppet `Package` resource can
#     normally accept.
#
# @param $mode
#   @see `deferred_resources::mode`
#
# @param $log_level
#   @see `deferred_resources::log_level`
#
class deferred_resources::packages (
  Variant[Hash, Array]                 $remove          = {},
  Variant[Hash, Array]                 $install         = {},
  Enum['latest','present','installed'] $install_ensure  = simplib::lookup('simp_options::package_ensure', { 'default_value' => 'installed' }),
  Hash                                 $default_options = {},
  Enum['warning','enforcing']          $mode            = $deferred_resources::mode,
  Simplib::PuppetLogLevel              $log_level       = $deferred_resources::log_level

) inherits deferred_resources {

  unless empty($remove) {
    deferred_resources{ "${module_name} Package remove":
      resources       => $remove,
      resource_type   => 'package',
      default_options => $default_options + { 'ensure' => 'absent' },
      mode            => $mode,
      log_level       => $log_level
    }
  }

  unless empty($install) {
    deferred_resources{ "${module_name} Package install":
      resources       => $install,
      resource_type   => 'package',
      default_options => $default_options + { 'ensure' => $install_ensure },
      mode            => $mode,
      log_level       => $log_level
    }
  }
}
