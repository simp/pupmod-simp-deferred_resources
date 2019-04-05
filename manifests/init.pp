# **WARNING:** This module is intended to help meet common policy requirements
# for packages being either present or absent on a system and is not meant for
# general usage. Make sure you understand the ramifications of what this module
# does to the Puppet catalog prior to using it outside of the SIMP framework.
#
# @param auto_include
#   Include all deferred_resources sub-classes
#
#   This should always be safe since the sub-classes do not actually do
#   anything to the system by default. However, you may find this option useful
#   if you are trying to debug a specific class or need to disable some of the
#   classes for a while independently.

# @param mode
#   If set to `enforcing` then the management classses will take action on the
#   system. If set to 'warning' a message will be printed noting what would
#   have taken place on the system but the catalog will not be updated.
#
# @param log_level
#   Set the log level for warning messages
#
class deferred_resources (
  Boolean                     $auto_include = true,
  Enum['warning','enforcing'] $mode         = 'warning',
  Simplib::PuppetLogLevel     $log_level    = 'info'
) {

  if $auto_include {
    include 'deferred_resources::packages'
    include 'deferred_resources::users'
    include 'deferred_resources::groups'
  }
}
