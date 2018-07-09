Puppet::Type.newtype(:deferred_packages) do
  @doc = <<-EOM
      This type will process after the catalog has been compiled but before it
      is applied.  It takes a list of packages and checks for the existence
      in the catalog for a resource for that package.  If a package
      is already defined differently in the catalog it prints out a warning message.
      Otherwise add a resource to the catalog to manage the package.

      If warning is set to false, do not print out any warning messages.

      If mode is set to 'warning' print out a list of resources
      that would have been created but don't add them to the catalog.

  EOM

  def initialize(args)
    super(args)
  end

  newparam(:name) do
    desc <<-EOM
      Static name assigned to this type.
    EOM

    isnamevar

  end

  newparam(:packages) do
    desc <<-EOM
      A hash or array of packages to add to the catalog.
    EOM

    validate do |value|
      unless  value.is_a?(Hash) || value.is_a?(Array)
        raise 'Expecting a Hash or Array for "packages" parameter.'
      end
    end

  end

  newparam(:default_options) do
    desc <<-EOM
      A hash of options to be used for all packages in the list.
    EOM

    validate do |value|
      unless   value.is_a?(Hash)
        raise 'Expecting a Hash for "default_options" parameter.'
      end
    end

    defaultto {}
  end


  newparam(:warning, :boolean => true) do
    desc <<-EOM
      If true will display warning messages.
    EOM
    newvalues(:true, :false)
    defaultto :true
  end

  newparam(:mode) do
    desc <<-EOM
       If set to enforcing, it will remove or add the packages in the lists if
       they are not already defined in a puppet manifest.

       If set to warning it will just issue a warning if the packages are installed
       or not, again only in a manifest.
    EOM
    validate do | value|
      unless ['enforcing','warning'].include?("#{value}")
        raise(ArgumentError,"Parameter 'mode' must be either 'enforcing' or 'warning'")
      end
    end

  end

  def merge_settings(pkgs,defaults)
    # Merge any default settings into the options and make sure
    # ensure and name attributes are set in options hash.
    returnhash = Hash.new
    pkgs.each { |p, opts|
      options = Hash.new
      options['name'] = p
      if opts.is_a?(Hash)
        options = options.merge(defaults.merge(opts))
      else
        options = options.merge(defaults)
      end
      returnhash[p] = options
    }
    returnhash
  end


  def process_list
    #@original parameters does not contain any processing done by the type so we have to
    #set the defaults.
    defaults = @original_parameters[:default_options]
    defaults || defaults = {}
    mode = @original_parameters[:mode]
    mode || mode = 'warning'
    warning = @original_parameters[:warning]

    allpkgs = self.merge_settings(@original_parameters[:packages],defaults)
    #
    # Go through the list of packages from the stig, check if a resource exists
    # and create resource or print message as appropriate.
    dump = allpkgs.each { |pkg, opts|
      res = @catalog.resource('Package', pkg)
      if res
        # The catalog has a resource for this package.  Check if they are trying
        # to perform the same action as this type.
        #
        # Prep message for if we need it.  Done here so code is not in two places
        msg = <<-EOM
Deferred_packages: Package resource #{pkg} was not created because it exists
in the catalog.  "ensure" setting is:
     deferred_packages setting:  #{opts['ensure']}
     catalog setting:            #{res[:ensure]}
       EOM

        Puppet.debug(msg)
        if warning
          case opts['ensure']
          when 'installed','present','latest'
            unless ['installed','present','latest',:installed, :latest, :present].include?(res[:ensure])
              Puppet.warning("#{msg}")
            end
          when 'absent','purge'
            unless ['absent',:absent,'purge',:purge].include?(res[:ensure])
              Puppet.warning("#{msg}")
            end
          else
            Puppet.warning("#{msg}")
          end
        end
      else
      # The catalog does not have a resource for this package.
         if Puppet[:noop] || mode == 'warning'
           Puppet.warning("Package #{opts['name']} with ensure #{opts['ensure']} would have been added to the system.")
         else
           catalog.create_resource('package',opts)
           Puppet.debug("Package #{pkg} with #{opts} was added to the catalog")
         end
      end
    }
    # Return nil because we don't actuall need to set an autorequire
    # resources.
    return nil
  end

  autorequire(:file) do
    # The list processing is done here to ensure that the catalog has been
    # compiled and all package definitions from manifests have been created.
    #
    self.process_list
   end

end
