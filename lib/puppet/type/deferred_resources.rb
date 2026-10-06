Puppet::Type.newtype(:deferred_resources) do
  @doc = <<~EOM
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

    A resource entry may set the reserved control option `override` to `true`,
    in which case a matching resource that already exists in the catalog will
    have all of the attributes specified on the entry forced onto it. An
    attribute with a `nil` value will be *removed* from the existing resource
    (e.g. unsetting `source` when specifying `content`). `override` is never
    passed on to the created resource.

    If mode is set to `warning`, instead of adding resources to the catalog,
    it prints out a list of resources that would have been added.
  EOM

  newparam(:name) do
    desc <<~EOM
      Unique name for this resource.
    EOM

    isnamevar
  end

  newparam(:default_options) do
    desc <<~EOM
      A Hash of options to be used for all resources.
    EOM

    defaultto({})

    validate do |value|
      unless value.is_a?(Hash)
        raise Puppet::Error, 'Expecting a Hash for :default_options'
      end

      if value.key?('override') && ![true, false].include?(value['override'])
        raise Puppet::Error, "The 'override' option in :default_options must be a Boolean"
      end
    end
  end

  newparam(:resource_type) do
    desc <<~EOM
      The type of Puppet resource that will be passed in :resources
    EOM

    newvalues(%r{.+})
  end

  newparam(:resources) do
    desc <<~EOM
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
      unless value.is_a?(Hash) || value.is_a?(Array)
        raise Puppet::Error, 'Expecting a Hash or Array for :resources'
      end

      if value.is_a?(Hash)
        value.each do |n, opts|
          next unless opts.is_a?(Hash)

          if opts.key?('override') && ![true, false].include?(opts['override'])
            raise Puppet::Error, "The 'override' option on resource '#{n}' must be a Boolean"
          end
        end
      end
    end
  end

  newparam(:log_level) do
    desc <<~EOM
      Set the message log level for notifications.
    EOM
    defaultto(:warning)

    newvalues(:alert, :crit, :debug, :notice, :emerg, :err, :info, :warning)
  end

  newparam(:mode) do
    desc <<~EOM
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
    type_class = Puppet::Type.type(self[:resource_type].to_s.downcase)

    # The resource type is user-provided data, so an unknown type must not
    # take down the entire catalog run when the resources would have been
    # created
    if type_class.nil?
      Puppet.send(self[:log_level], "deferred_resources: Unknown resource type '#{self[:resource_type]}'; skipping all entries")

      next []
    end

    # Catalog aliases for isomorphic types are stored by composite uniqueness
    # key (e.g. `[provider, name]` for packages), so a resource that manages
    # the same underlying entity under a different title cannot be found by a
    # title lookup and would raise a duplicate resource error at creation
    # time. Build a namevar => resource map up front so that those resources
    # can be found without rescanning the catalog for every entry.
    existing_by_name = nil
    if type_class.isomorphic?
      existing_by_name = {}

      catalog.resources.each do |r|
        existing_by_name[r.name.to_s] ||= r if r.is_a?(type_class)
      end
    end

    # Go through the provided resources, check if a resource exists.
    # Create the resource or print message as appropriate
    self[:resources].each do |rname, opts|
      # Symbolize the keys after merging for direct comparison later
      opts = self[:default_options].merge(opts).each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
      end

      # 'override' is a control option for this type, never an attribute of
      # the target resource
      override = opts.delete(:override)

      # Get the easily searchable name
      resource_type = self[:resource_type].to_s.capitalize

      # Directly pull the existing resource if it exists
      existing_resource = catalog.resource(resource_type, rname)

      # Fall back to a lookup by the explicit namevar so that we do not try to
      # add a resource whose namevar collides with an existing resource that
      # was declared under a different title
      if !existing_resource && opts[:name] && (opts[:name] != rname)
        existing_resource = catalog.resource(resource_type, opts[:name])
      end

      # Finally, fall back to the namevar map to catch existing resources that
      # manage the same underlying entity under an unrelated title
      if !existing_resource && existing_by_name
        existing_resource = existing_by_name[(opts[:name] || rname).to_s]
      end

      # A user-friendly name for the resource to add to the logs
      resource_log_name = "#{resource_type}[#{rname}]"

      override_attrs = opts.keys - [:name]

      if existing_resource
        if override && !override_attrs.empty?
          if self[:mode] == :enforcing
            # Force every attribute specified on the entry onto the existing
            # resource; a nil value removes the attribute entirely
            override_attrs.each do |attr|
              if opts[attr].nil?
                if existing_resource.parameters.keys.include?(attr)
                  Puppet.debug("deferred_resources: Unsetting attribute '#{attr}' on existing resource #{resource_log_name}")

                  existing_resource.delete(attr)
                end
              else
                Puppet.debug("deferred_resources: Setting value of '#{attr}' to '#{opts[attr]}' on existing resource #{resource_log_name}")

                existing_resource[attr] = opts[attr]
              end
            end
          else
            Puppet.send(self[:log_level], %(deferred_resources: Would have overridden attributes '#{override_attrs.join("', '")}' on existing resource #{resource_log_name}))
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
        # nil-valued attributes only make sense as an unset instruction for
        # overrides, so they must not be passed to a new resource
        create_opts = opts.reject { |_k, v| v.nil? }

        opts_minus_name = create_opts.dup
        opts_minus_name.delete(:name)

        if self[:mode] == :enforcing
          catalog.create_resource(resource_type, create_opts)

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
