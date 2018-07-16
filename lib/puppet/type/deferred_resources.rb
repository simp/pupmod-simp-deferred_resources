Puppet::Type.newtype(:deferred_resources) do
  @doc = <<-EOM
      WARNING: This type is **NOT** meant to be called directly. Please use the
      helper classes in the module.

      This type will process after the catalog has been compiled but before it
      is applied.  It takes a list of resources and checks for the existence of
      that resource in the compiled catalog. If the resource has already been
      defined in the catalog, it prints out a message that an action will
      not be performed.

      If mode is set to `warning`, instead of adding resources to the catalog,
      it prints out a list of resources that would have been added.
  EOM

  newparam(:name) do
    desc <<-EOM
      Unique name for this resource.
    EOM

    isnamevar
  end

  newparam(:default_options) do
    desc <<-EOM
      A Hash of options to be used for all resources.
    EOM

    defaultto(Hash.new)

    validate do |value|
      unless   value.is_a?(Hash)
        raise 'Expecting a Hash for :default_options'
      end
    end
  end

  newparam(:resource_type) do
    desc <<-EOM
      The type of Puppet resource that will be passed in :resources
    EOM

    newvalues(/.+/)
  end

  newparam(:resources) do
    desc <<-EOM
      A Hash or Array of resources to add to the catalog.
    EOM

    munge do |value|
      if value.is_a?(Array)
        new_value = {}

        value.each do |entry|
          new_value[entry] = {}
        end

        value = new_value
      end

      value.each do |n, opts|
        opts = {} unless opts.is_a?(Hash)

        opts['name'] = n unless opts['name']

        value[n] = opts
      end

      value
    end

    validate do |value|
      unless  value.is_a?(Hash) || value.is_a?(Array)
        raise 'Expecting a Hash or Array for :resources'
      end
    end
  end

  newparam(:log_level) do
    desc <<-EOM
      Set the message log level for notifications.
    EOM
    defaultto(:warning)

    newvalues(:alert, :crit, :debug, :notice, :emerg, :err, :info, :warning)
  end

  newparam(:mode) do
    desc <<-EOM
      `enforcing` => Actually add the resource to the catalog post-compilation
      `warning`   => Tell the user what would be done but do not actually alter
                     the catalog.
    EOM

    defaultto(:warning)

    newvalues(:enforcing, :warning)
  end

  validate do
    unless self[:resource_type]
      raise(Puppet::Error, 'You must specify :resource_type')
    end

    unless self[:resources]
      raise(Puppet::Error, 'You must specify :resources')
    end
  end

  autorequire(:file) do
    # Go through the provided resources, check if a resource exists.
    # Create the resource or print message as appropriate
    self[:resources].each do |rname, opts|
      # Symbolize the keys after merging for comparison later
      opts = self[:default_options].merge(opts).inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}

      resource_type = self[:resource_type].to_s.capitalize
      existing_resource = catalog.resource(resource_type, rname)

      resource_log_name = "#{resource_type}[#{rname}]"

      if existing_resource
        # If the options are different we need to let the user know since that
        # is a potential policy violation.
        if (Array(opts) - Array(existing_resource.to_hash)).empty?
          Puppet.debug("deferred_resources: Ignoring existing resource #{resource_log_name}")
        else
          Puppet.send(self[:log_level], "deferred_resources: Existing resource '#{resource_log_name}' at '#{existing_resource.file}:#{existing_resource.line}' has options that differ from deferred_resources::<x> parameters")
        end
      else
        opts_minus_name = opts.dup
        opts_minus_name.delete(:name)
        if self[:mode] == :enforcing
          catalog.create_resource(resource_type, opts)

          Puppet.debug("deferred_resources: Created #{resource_log_name} with #{opts_minus_name}")
        else
          Puppet.send(self[:log_level], "deferred_resources: Would have created #{resource_log_name} with #{opts_minus_name}")
        end
      end
    end

    # Just return an empty list
    Array.new
  end
end
