# **WARNING:** This module is intended to help meet common policy requirements
# for packages being either present or absent on a system and is not meant for
# general usage. Make sure you understand the ramifications of what this module
# does to the Puppet catalog prior to using it outside of the SIMP framework.
#
# @param $mode
#   If set to `enforcing` then the management classses will take action on the
#   system. If set to 'warning' a message will be printed noting what would
#   have taken place on the system but the catalog will not be updated.
#
# @param $log_level
#   Set the log level for warning messages
#
class deferred_resources (
  Enum['warning','enforcing'] $mode      = 'warning',
  Simplib::PuppetLogLevel     $log_level = 'info'
) { }
