# This module will  takes two lists of packages, on to ensoure removed
# and one to ensure installed.  After all manifests have ben processed,
# it will go through the catalog and if a definition for the package
# does not exist it will add it.
#
# This module will fail if a package is defined more than once in the two lists.
#
# @param $packages_remove
#   A list of packages to remove.  A Hash can be used to add
#   extra attributes for the package, but the ensure attribute
#   will be overwritten if it is included.
#
# @param $packages_install
#   A list of packages to install.  A Hash can be used to add
#   extra attributes for the package, but the ensure attribute
#   will be overwritten if it is included.
#
# @param $default_options
#   A Hash of options to apply to all packages (both remove and install.
#   If ensure is entered in these options it will be overwritten.
#
# @param $mode
#   If set to 'enforcing' a package resource will be added to the catalog
#   If set to 'warning' a message will be printed that resource would have
#      been added to the catalog but the catalog will not be updated.
#
# @param $enable_warnings
#   If a package already exists in the catalog a message will be printed
#   out.  If this is set to false these messages are supressed.
#   This does not suppress information messages printed out it mode is
#   set to warning.

class deferred_resources(
  Variant[Hash, Array]          $packages_remove   = {},
  Variant[Hash, Array]          $packages_install  = {},
  Hash                          $default_options   = {},
  Enum['warning','enforcing']   $mode              = 'warning',
  Boolean                       $enable_warnings   = true,
  String                        $package_ensure    = simplib::lookup('simp_options::package_ensure', { 'default_value' => 'installed' })

){

  $_default_opts_remove = $default_options + { 'ensure'  => 'absent' }
  $_default_opts_install = $default_options + { 'ensure' => $package_ensure }
  if size($packages_remove) > 0 {
    deferred_packages{ 'compliance packages remove':
      packages        => $packages_remove,
      default_options => $_default_opts_remove,
      mode            => $mode,
      warning         => $enable_warnings
    }
  }
  if size($packages_install) > 0 {
    deferred_packages{ 'compliance packages install':
      packages        => $packages_install,
      default_options => $_default_opts_install,
      mode            => $mode,
      warning         => $enable_warnings
    }
  }
}

