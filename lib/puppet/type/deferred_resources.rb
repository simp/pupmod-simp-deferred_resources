Puppet::Type.newtype(:deferred_resources) do
  @doc = <<-EOM
      *** DANGER ***

      THIS RESOURCE TYPE DOES THINGS THAT MAY BE CONFUSING MAKE SURE YOU FULLY
      UNDERSTAND HOW IT WORKS PRIOR TO USING IT

      *** DANGER ***

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

    defaultto({})

    validate do |value|
      unless value.is_a?(Hash)
        raise Puppet::Error, 'Expecting a Hash for :default_options'
      end
    end
  end

  newparam(:resource_type) do
    desc <<-EOM
      The type of Puppet resource that will be passed in :resources
    EOM

    newvalues(%r{.+})
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
        raise Puppet::Error, 'Expecting a Hash or Array for :resources'
      end
    end
  end

  newparam(:override_existing_attributes) do
    desc <<-EOM
     A Hash or Array of items that should be updated on existing attributes if
     they exist.

      This is basically a controlled resource collector and absolutely must not
      be taken lightly when used since it will affect existing resources in
      your catalog.

      If you want to be explicit, use a Resource Collector and do not set this.

      If a Hash is passed, each key is the attribute that can be overridden and
      an optional hash of options can be passed with the following meanings.

        * 'invalidates':
          * An Array of entries that this particular parameter invalidates.
            This means that the items in the list will be set to `nil` in the
            overridden resource.
    EOM

    munge do |value|
      if value.is_a?(Array)
        value = Hash[value.map { |x| [x, {}] }]
      end

      value.keys.each do |k|
        value[k] = {} if value[k].nil?
      end

      value
    end

    validate do |value|
      unless (value.is_a?(Hash) || value.is_a?(Array)) && !value.empty?
        raise Puppet::Error, 'Expecting an Array or Hash with contents for :override_existing_attributes'
      end

      valid_control_opts = [
        'invalidates',
      ]

      if value.is_a?(Hash)
        value.each_pair do |attr, opts|
          next unless opts&.is_a?(Hash)
          invalid_control_opts = (opts.keys - valid_control_opts)

          unless invalid_control_opts.empty?
            raise Puppet::Error, %(Unknown control options '#{invalid_control_opts.join("', '")}' passed in the :override_existing_attributes Hash)
          end

          unless opts['invalidates'].is_a?(Array)
            raise Puppet::Error, "You must pass an Array of attributes to override for '#{attr}' in the :override_existing_attributes Hash"
          end
        end
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
      # Symbolize the keys after merging for direct comparison later
      opts = self[:default_options].merge(opts).each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
      end

      # Get the easily searchable name
      resource_type = self[:resource_type].to_s.capitalize

      # Directly pull the existing resource if it exists
      existing_resource = catalog.resource(resource_type, rname)

      # A user-friendly name for the resource to add to the logs
      resource_log_name = "#{resource_type}[#{rname}]"

      if existing_resource
        if self[:override_existing_attributes]
          if self[:mode] == :enforcing
            # Update the targeted list of attributes if they are present and
            # honor whatever options are passed
            self[:override_existing_attributes].each_pair do |attr, existing_resource_opts|
              next unless opts[attr.to_sym]
              if existing_resource_opts['invalidates']
                Array(existing_resource_opts['invalidates']).each do |to_invalidate|
                  to_invalidate = to_invalidate.to_sym

                  Puppet.debug("deferred_resources: Invalidating attribute '#{to_invalidate}' on existing resource #{resource_log_name}")

                  if existing_resource.parameters.keys.include?(to_invalidate)
                    existing_resource.delete(to_invalidate)
                  end
                end
              end

              Puppet.debug("deferred_resources: Setting value of '#{attr}' to '#{opts[attr]}' on existing resource #{resource_log_name}")

              existing_resource[attr] = opts[attr.to_sym]
            end
          else
            Puppet.send(self[:log_level], %(deferred_resources: Would have overridden attributes '#{self[:override_existing_attributes].keys.join("', '")}' on existing resource #{resource_log_name}))
          end
        elsif (Array(opts) - Array(existing_resource.to_hash)).empty?
          # If the options are different we need to let the user know since
          # that is a potential policy violation.
          Puppet.debug("deferred_resources: Ignoring existing resource #{resource_log_name}")
        else
          Puppet.send(self[:log_level],
"deferred_resources: Existing resource '#{resource_log_name}' at '#{existing_resource.file}:#{existing_resource.line}' has options that differ from deferred_resources::<x> parameters")
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
    []
  end
end
