#!/usr/bin/env rspec

require 'spec_helper'

deferred_resources_type = Puppet::Type.type(:deferred_resources)

describe deferred_resources_type do
  context 'when setting parameters' do
    context ':resource_type' do
      it 'should fail if not passed' do
        expect{
          deferred_resources_type.new(
            :name => 'foo',
            :resources => ['foo']
          )
        }.to raise_error(/must specify :resource_type/)
      end
    end

    context ':resources' do
      it 'should accept a Hash' do
        resource = deferred_resources_type.new(
          :name => 'foo',
          :resource_type => 'package',
          :resources => {'mypackage' => :undef}
        )

        expect(resource[:name]).to eq('foo')
        expect(resource[:resources]).to eq({
          'mypackage' => {
            'name' => 'mypackage'
          }
        })
      end

      it 'should accept an Array' do
        resource = deferred_resources_type.new(
          :name => 'foo',
          :resource_type => 'package',
          :resources => ['mypackage','myotherpackage']
        )

        expect(resource[:resources]).to eq({
          'mypackage' => {
            'name' => 'mypackage'
          },
          'myotherpackage' => {
            'name' => 'myotherpackage'
          }
        })
      end

      it 'should fail if not passed' do
        expect{
          deferred_resources_type.new(
            :name => 'foo',
            :resource_type => 'package'
          )
        }.to raise_error(/must specify :resources/)
      end
    end

    context ':default_options' do
      it 'should accept vaild values' do
        resource = deferred_resources_type.new(
          :name => 'foo',
          :resource_type => 'package',
          :resources => ['mypackage'],
          :default_options => { 'foo' => 'bar' }
        )

        expect(resource[:default_options]).to eq({ 'foo' => 'bar'})
      end

      it 'should fail on invalid values' do
        expect {
          deferred_resources_type.new(
            :name => 'foo',
            :resource_type => 'package',
            :resources => ['mypackage'],
            :default_options => 'foo'
          )
        }.to raise_error(/xpecting a Hash/)
      end
    end

    context ':log_level' do
      it 'should accept a valid value' do
        resource = deferred_resources_type.new(
          :name => 'foo',
          :resource_type => 'package',
          :resources => ['mypackage'],
          :log_level => 'warning'
        )

        expect(resource[:log_level]).to eq(:warning)
      end
    end

    context ':mode' do
      it 'should accept a valid value' do
        resource = deferred_resources_type.new(
          :name => 'foo',
          :resource_type => 'package',
          :resources => ['mypackage'],
          :mode => 'enforcing'
        )

        expect(resource[:mode]).to eq(:enforcing)
      end
    end
  end

  context 'when processing the catalog' do
    before(:each) do
      @catalog = Puppet::Resource::Catalog.new

      Puppet::Type::Deferred_resources.any_instance.stubs(:catalog).returns(@catalog)
    end

    context 'when enforcing' do
      it 'should add the new resources to the catalog' do
        resource = deferred_resources_type.new(
          :name => 'foo',
          :resource_type => 'package',
          :resources => ['mypackage'],
          :mode => 'enforcing'
        )

        resource.autorequire

        expect(@catalog.resource('Package', 'mypackage')).to_not be_nil
      end

      it 'should skip matching existing resources' do
        resource = deferred_resources_type.new(
          :name => 'foo',
          :resource_type => 'package',
          :resources => ['mypackage'],
          :mode => 'enforcing'
        )

        @catalog.create_resource('Package', {'name' => 'mypackage'})

        Puppet.expects(:debug).with('deferred_resources: Ignoring existing resource Package[mypackage]').once

        resource.autorequire
      end

      it 'should log on an existing resource with different options' do
        resource = deferred_resources_type.new(
          :name => 'foo',
          :resource_type => 'package',
          :resources => {
            'mypackage' => {
              'ensure' => 'installed'
            }
          },
          :mode => 'enforcing'
        )

        @catalog.create_resource('Package', {'name' => 'mypackage', 'ensure' => 'absent'})

        Puppet.expects(:send).with(:warning, "deferred_resources: Existing resource 'Package[mypackage]' at ':' has options that differ from deferred_resources::<x> parameters").once

        resource.autorequire
      end
    end

    context 'when warning' do
      it 'should not add the new resources to the catalog' do
        resource = deferred_resources_type.new(
          :name => 'foo',
          :resource_type => 'package',
          :resources => ['mypackage'],
          :mode => 'warning',
          :default_options => { 'ensure' => 'absent' }
        )

        Puppet.expects(:send).with(:warning, 'deferred_resources: Would have created Package[mypackage] with {:ensure=>"absent"}').once

        resource.autorequire

        expect(@catalog.resource('Package', 'mypackage')).to be_nil
      end
    end
  end
end
