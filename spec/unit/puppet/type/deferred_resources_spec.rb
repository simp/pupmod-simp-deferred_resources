#!/usr/bin/env rspec

require 'spec_helper'

deferred_resources_type = Puppet::Type.type(:deferred_resources)

describe deferred_resources_type do
  context 'when setting parameters' do
    context ':resource_type' do
      it 'should fail if not passed' do
        expect{
          deferred_resources_type.new(
            :name      => 'foo',
            :resources => ['foo']
          )
        }.to raise_error(/must specify :resource_type/)
      end
    end

    context ':resources' do
      it 'should accept a Hash' do
        resource = deferred_resources_type.new(
          :name          => 'foo',
          :resource_type => 'package',
          :resources     => {'mypackage' => :undef}
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
          :name          => 'foo',
          :resource_type => 'package',
          :resources     => ['mypackage','myotherpackage']
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
          :name            => 'foo',
          :resource_type   => 'package',
          :resources       => ['mypackage'],
          :default_options => { 'foo' => 'bar' }
        )

        expect(resource[:default_options]).to eq({ 'foo' => 'bar'})
      end

      it 'should fail on invalid values' do
        expect {
          deferred_resources_type.new(
            :name            => 'foo',
            :resource_type   => 'package',
            :resources       => ['mypackage'],
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
          :resources     => ['mypackage'],
          :log_level     => 'warning'
        )

        expect(resource[:log_level]).to eq(:warning)
      end
    end

    context ':mode' do
      it 'should accept a valid value' do
        resource = deferred_resources_type.new(
          :name => 'foo',
          :resource_type => 'package',
          :resources     => ['mypackage'],
          :mode          => 'enforcing'
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
          :name          => 'foo',
          :resource_type => 'package',
          :resources     => ['mypackage'],
          :mode          => 'enforcing'
        )

        resource.autorequire

        expect(@catalog.resource('Package', 'mypackage')).to_not be_nil
      end

      it 'should skip matching existing resources' do
        resource = deferred_resources_type.new(
          :name          => 'foo',
          :resource_type => 'package',
          :resources     => ['mypackage'],
          :mode          => 'enforcing'
        )

        @catalog.create_resource('Package', {'name' => 'mypackage'})

        Puppet.expects(:debug).with('deferred_resources: Ignoring existing resource Package[mypackage]').once

        resource.autorequire
      end

      it 'should log on an existing resource with different options' do
        resource = deferred_resources_type.new(
          :name => 'foo',
          :resource_type => 'package',
          :resources     => {
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

      context 'when overriding resources' do
        before(:each) do
          @resource = deferred_resources_type.new(
            :name                         => 'foo',
            :resource_type                => 'file',
            :mode                         => 'enforcing',
            :override_existing_attributes => [ 'owner', 'group', 'content' ],
            :resources                    => {
              '/tmp/test' => {
                'ensure'  => 'file',
                'owner'   => 'bob',
                'group'   => 'alice',
                'content' => 'Some stuff',
                # This should be ignored
                'mode'    => '0777'
              }
            }
          )

          @catalog.create_resource('File', {
            'name'    => '/tmp/test',
            'ensure'  => 'file',
            'owner'   => 'root',
            'group'   => 'root',
            'content' => 'Test',
            'mode'    => '0644'
          })
        end

        it 'should override attributes in an existing catalog resource' do
          @resource.autorequire

          result = @catalog.resource('File[/tmp/test]')

          expect(result[:owner]).to eq('bob')
          expect(result[:group]).to eq('alice')
          expect(result.parameter(:content).actual_content).to eq('Some stuff')
          expect(result[:mode]).to eq('644')
        end

        it 'should not affect unrelated resources' do
          @catalog.create_resource('File', {
            'name'    => '/tmp/test2',
            'ensure'  => 'file',
            'owner'   => 'root',
            'group'   => 'root',
            'content' => 'Test',
            'mode'    => '0644'
          })

          @resource.autorequire

          result = @catalog.resource('File[/tmp/test]')

          expect(result[:owner]).to eq('bob')
          expect(result[:group]).to eq('alice')
          expect(result.parameter(:content).actual_content).to eq('Some stuff')
          expect(result[:mode]).to eq('644')

          pristine_result = @catalog.resource('File[/tmp/test2]')

          expect(pristine_result[:owner]).to eq('root')
          expect(pristine_result[:group]).to eq('root')
          expect(pristine_result.parameter(:content).actual_content).to eq('Test')
          expect(pristine_result[:mode]).to eq('644')
        end
      end

      context 'when overriding and invalidating attributes' do
        it 'should override attributes in an existing catalog resource and invalidate "source"' do
          @resource = deferred_resources_type.new(
            :name                         => 'foo',
            :resource_type                => 'file',
            :mode                         => 'enforcing',
            :override_existing_attributes => {
              'owner'   => nil,
              'group'   => nil,
              'content' => {
                'invalidates' => ['source']
              }
            },
            :resources                    => {
              '/tmp/test' => {
                'ensure'  => 'file',
                'owner'   => 'bob',
                'group'   => 'alice',
                'content' => 'Some stuff',
                # This should be ignored
                'mode'    => '0777'
              }
            }
          )

          @catalog.create_resource('File', {
            'name'    => '/tmp/test',
            'ensure'  => 'file',
            'owner'   => 'root',
            'group'   => 'root',
            'source' => 'puppet:///my.server/test',
            'mode'    => '0644'
          })

          @resource.autorequire

          result = @catalog.resource('File[/tmp/test]')

          expect(result[:owner]).to eq('bob')
          expect(result[:group]).to eq('alice')
          expect(result.parameter(:content).actual_content).to eq('Some stuff')
          expect(result[:mode]).to eq('644')
          expect(result[:source]).to be_nil
        end

        it 'should not remove attributes that are not present in the override resource' do
          @resource = deferred_resources_type.new(
            :name                         => 'foo',
            :resource_type                => 'file',
            :mode                         => 'enforcing',
            :override_existing_attributes => {
              'owner'   => nil,
              'group'   => nil,
              'content' => {
                'invalidates' => ['source']
              }
            },
            :resources                    => {
              '/tmp/test' => {
                'ensure'  => 'file',
                'owner'   => 'bob',
                'group'   => 'alice',
                # This should be ignored
                'mode'    => '0777'
              }
            }
          )

          @catalog.create_resource('File', {
            'name'    => '/tmp/test',
            'ensure'  => 'file',
            'owner'   => 'root',
            'group'   => 'root',
            'source' => 'puppet:///my.server/test',
            'mode'    => '0644'
          })

          @resource.autorequire

          result = @catalog.resource('File[/tmp/test]')

          expect(result[:owner]).to eq('bob')
          expect(result[:group]).to eq('alice')
          expect(result[:content]).to be_nil
          expect(result[:mode]).to eq('644')
          expect(result[:source]).to eq(['puppet:///my.server/test'])
        end

        it 'should fail on an invalid override option' do
          expect {
            deferred_resources_type.new(
              :name                         => 'foo',
              :resource_type                => 'file',
              :mode                         => 'enforcing',
              :override_existing_attributes => {
                'owner'   => nil,
                'group'   => nil,
                'content' => {
                  'watermelons' => ['cheese']
                }
              },
              :resources                    => {
                '/tmp/test' => {
                  'mode' => '0777'
                }
              }
            )
          }.to raise_error(/Unknown control options 'watermelons'/)
        end

        it 'should fail if not passed an Array of attributes to override' do
          expect {
            deferred_resources_type.new(
              :name                         => 'foo',
              :resource_type                => 'file',
              :mode                         => 'enforcing',
              :override_existing_attributes => {
                'owner'   => nil,
                'group'   => nil,
                'content' => {
                  'invalidates' => 'cheese'
                }
              },
              :resources                    => {
                '/tmp/test' => {
                  'mode' => '0777'
                }
              }
            )
          }.to raise_error(/You must pass an Array of attributes to override for 'content'/)
        end
      end
    end

    context 'when warning' do
      it 'should not add the new resources to the catalog' do
        resource = deferred_resources_type.new(
          :name            => 'foo',
          :resource_type   => 'package',
          :resources       => ['mypackage'],
          :mode            => 'warning',
          :default_options => { 'ensure' => 'absent' }
        )

        Puppet.expects(:send).with(:warning, 'deferred_resources: Would have created Package[mypackage] with {:ensure=>"absent"}').once

        resource.autorequire

        expect(@catalog.resource('Package', 'mypackage')).to be_nil
      end

      it 'should not override any existing resources' do
          @resource = deferred_resources_type.new(
            :name                         => 'foo',
            :resource_type                => 'file',
            :mode                         => 'warning',
            :override_existing_attributes => {
              'owner'   => nil,
              'group'   => nil,
              'content' => {
                'invalidates' => ['source']
              }
            },
            :resources                    => {
              '/tmp/test' => {
                'ensure'  => 'file',
                'owner'   => 'bob',
                'group'   => 'alice',
                'content' => 'Some stuff',
                # This should be ignored
                'mode'    => '0777'
              }
            }
          )

          @catalog.create_resource('File', {
            'name'    => '/tmp/test',
            'ensure'  => 'file',
            'owner'   => 'root',
            'group'   => 'root',
            'source' => 'puppet:///my.server/test',
            'mode'    => '0644'
          })

          Puppet.expects(:send).with(:warning, %{deferred_resources: Would have overridden attributes 'owner', 'group', 'content' on existing resource File[/tmp/test]}).once

          @resource.autorequire

          result = @catalog.resource('File[/tmp/test]')

          expect(result[:owner]).to eq('root')
          expect(result[:group]).to eq('root')
          expect(result[:source]).to eq(['puppet:///my.server/test'])
          expect(result[:content]).to be_nil
          expect(result[:mode]).to eq('644')
      end
    end
  end
end
