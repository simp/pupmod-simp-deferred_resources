#!/usr/bin/env rspec

require 'spec_helper'

deferred_packages_type = Puppet::Type.type(:deferred_packages)

describe deferred_packages_type do
  before(:each) do
    @catalog = Puppet::Resource::Catalog.new
    Puppet::Type::Deferred_packages.any_instance.stubs(:catalog).returns(@catalog)
  end

  context 'when setting parameters' do
    it 'should accept a name parameter and a packages hash' do
      resource = deferred_packages_type.new :name => 'foo', :packages => {'mypackage' => :undef }
      expect(resource[:name]).to eq('foo')
      expect(resource[:packages]).to eq({'mypackage' => :undef })
    end

    it 'should accept a packages array parameter' do
      resource = deferred_packages_type.new :name => 'foo', :packages => ['mypackage','myotherpackage']
      expect(resource[:packages]).to eq(['mypackage','myotherpackage'])
    end
  end
end
