#!/usr/bin/env rspec

require 'spec_helper'

describe Puppet::Type.type(:deferred_resources) do
  let(:deferred_resources_type) { described_class }

  context 'when setting parameters' do
    context ':resource_type' do
      it 'fails if not passed' do
        expect {
          deferred_resources_type.new(
            name: 'foo',
            resources: ['foo'],
          )
        }.to raise_error(%r{must specify :resource_type})
      end
    end

    context ':resources' do
      it 'accepts a Hash' do
        resource = deferred_resources_type.new(
          name: 'foo',
          resource_type: 'package',
          resources: { 'mypackage' => :undef },
        )

        expect(resource[:name]).to eq('foo')
        expect(resource[:resources]).to eq(
          'mypackage' => {
            'name' => 'mypackage',
          },
        )
      end

      it 'accepts an Array' do
        resource = deferred_resources_type.new(
          name: 'foo',
          resource_type: 'package',
          resources: ['mypackage', 'myotherpackage'],
        )

        expect(resource[:resources]).to eq(
          'mypackage' => {
            'name' => 'mypackage',
          },
          'myotherpackage' => {
            'name' => 'myotherpackage',
          },
        )
      end

      it 'fails if not passed' do
        expect {
          deferred_resources_type.new(
            name: 'foo',
            resource_type: 'package',
          )
        }.to raise_error(%r{must specify :resources})
      end
    end

    context ':default_options' do
      it 'accepts vaild values' do
        resource = deferred_resources_type.new(
          name: 'foo',
          resource_type: 'package',
          resources: ['mypackage'],
          default_options: { 'foo' => 'bar' },
        )

        expect(resource[:default_options]).to eq({ 'foo' => 'bar' })
      end

      it 'fails on invalid values' do
        expect {
          deferred_resources_type.new(
            name: 'foo',
            resource_type: 'package',
            resources: ['mypackage'],
            default_options: 'foo',
          )
        }.to raise_error(%r{xpecting a Hash})
      end
    end

    context ':log_level' do
      it 'accepts a valid value' do
        resource = deferred_resources_type.new(
          name: 'foo',
          resource_type: 'package',
          resources: ['mypackage'],
          log_level: 'warning',
        )

        expect(resource[:log_level]).to eq(:warning)
      end
    end

    context ':mode' do
      it 'accepts a valid value' do
        resource = deferred_resources_type.new(
          name: 'foo',
          resource_type: 'package',
          resources: ['mypackage'],
          mode: 'enforcing',
        )

        expect(resource[:mode]).to eq(:enforcing)
      end
    end
  end

  context 'when processing the catalog' do
    let(:catalog) { Puppet::Resource::Catalog.new }

    before(:each) do
      # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(Puppet::Type::Deferred_resources).to receive(:catalog).and_return(catalog)
      # rubocop:enable RSpec/AnyInstance
    end

    context 'with an unknown resource type' do
      it 'skips all entries without failing the run' do
        resource = deferred_resources_type.new(
          name: 'foo',
          resource_type: 'watermelon',
          resources: ['seedless'],
          mode: 'enforcing',
        )

        expect(Puppet).to receive(:send).with(:warning, %(deferred_resources: Unknown resource type 'watermelon'; skipping all entries)).once

        expect { resource.autorequire }.not_to raise_error
      end
    end

    context 'when enforcing' do
      it 'adds the new resources to the catalog' do
        resource = deferred_resources_type.new(
          name: 'foo',
          resource_type: 'package',
          resources: ['mypackage'],
          mode: 'enforcing',
        )

        resource.autorequire

        expect(catalog.resource('Package', 'mypackage')).not_to be_nil
      end

      it 'skips matching existing resources' do
        resource = deferred_resources_type.new(
          name: 'foo',
          resource_type: 'package',
          resources: ['mypackage'],
          mode: 'enforcing',
        )

        catalog.create_resource('Package', { 'name' => 'mypackage' })

        expect(Puppet).to receive(:debug).with('deferred_resources: Ignoring existing resource Package[mypackage]').once

        resource.autorequire
      end

      it 'does not add a duplicate when an entry namevar matches an existing resource with a different title' do
        resource = deferred_resources_type.new(
          name: 'foo',
          resource_type: 'package',
          resources: {
            'mypackage' => {
              'name' => 'realpackage',
            },
          },
          mode: 'enforcing',
        )

        catalog.create_resource('Package', { 'name' => 'realpackage' })

        expect(Puppet).to receive(:debug).with('deferred_resources: Ignoring existing resource Package[mypackage]').once

        expect { resource.autorequire }.not_to raise_error

        expect(catalog.resource('Package', 'mypackage')).to be_nil
      end

      it 'skips an existing resource whose namevar matches the entry title' do
        resource = deferred_resources_type.new(
          name: 'foo',
          resource_type: 'package',
          resources: ['realpackage'],
          mode: 'enforcing',
        )

        catalog.create_resource('Package', { 'title' => 'some-other-title', 'name' => 'realpackage' })

        expect(Puppet).to receive(:debug).with('deferred_resources: Ignoring existing resource Package[realpackage]').once

        expect { resource.autorequire }.not_to raise_error

        expect(catalog.resource('Package', 'realpackage')).to be_nil
        expect(catalog.resource('Package', 'some-other-title')).not_to be_nil
      end

      it 'logs on an existing resource with different options' do
        resource = deferred_resources_type.new(
          name: 'foo',
          resource_type: 'package',
          resources: {
            'mypackage' => {
              'ensure' => 'installed',
            },
          },
          mode: 'enforcing',
        )

        catalog.create_resource('Package', { 'name' => 'mypackage', 'ensure' => 'absent' })

        expect(Puppet).to receive(:send).with(:warning, "deferred_resources: Existing resource 'Package[mypackage]' at ':' has options that differ from deferred_resources::<x> parameters").once

        resource.autorequire
      end

      context 'when overriding resources' do
        let(:resource) do
          deferred_resources_type.new(
            name: 'foo',
            resource_type: 'file',
            mode: 'enforcing',
            resources: {
              '/tmp/test' => {
                'ensure'   => 'file',
                'owner'    => 'bob',
                'group'    => 'alice',
                'content'  => 'Some stuff',
                'override' => true,
              },
            },
          )
        end

        before(:each) do
          catalog.create_resource(
            'File',
            {
              'name'    => '/tmp/test',
              'ensure'  => 'file',
              'owner'   => 'root',
              'group'   => 'root',
              'content' => 'Test',
              'mode'    => '0644',
            },
          )
        end

        it 'overrides all specified attributes on an existing catalog resource' do
          resource.autorequire

          result = catalog.resource('File[/tmp/test]')

          expect(result[:owner]).to eq('bob')
          expect(result[:group]).to eq('alice')
          expect(result.parameter(:content).actual_content).to eq('Some stuff')
          # Not specified on the entry, so untouched
          expect(result[:mode]).to match(%r{^0?644$})
        end

        it 'does not affect unrelated resources' do
          catalog.create_resource(
            'File',
            {
              'name'    => '/tmp/test2',
              'ensure'  => 'file',
              'owner'   => 'root',
              'group'   => 'root',
              'content' => 'Test',
              'mode'    => '0644',
            },
          )

          resource.autorequire

          result = catalog.resource('File[/tmp/test]')

          expect(result[:owner]).to eq('bob')
          expect(result[:group]).to eq('alice')
          expect(result.parameter(:content).actual_content).to eq('Some stuff')
          expect(result[:mode]).to match(%r{^0?644$})

          pristine_result = catalog.resource('File[/tmp/test2]')

          expect(pristine_result[:owner]).to eq('root')
          expect(pristine_result[:group]).to eq('root')
          expect(pristine_result.parameter(:content).actual_content).to eq('Test')
          expect(pristine_result[:mode]).to match(%r{^0?644$})
        end

        it 'does not touch an existing resource when override is not set' do
          plain_resource = deferred_resources_type.new(
            name: 'foo',
            resource_type: 'file',
            mode: 'enforcing',
            resources: {
              '/tmp/test' => {
                'ensure' => 'file',
                'owner'  => 'bob',
              },
            },
          )

          expect(Puppet).to receive(:send).with(:warning, %r{Existing resource 'File\[/tmp/test\]' .* has options that differ}).once

          plain_resource.autorequire

          result = catalog.resource('File[/tmp/test]')

          expect(result[:owner]).to eq('root')
        end
      end

      context 'when overriding and unsetting attributes' do
        let(:resource) do
          deferred_resources_type.new(
            name: 'foo',
            resource_type: 'file',
            mode: 'enforcing',
            resources: {
              '/tmp/test' => {
                'ensure'   => 'file',
                'owner'    => 'bob',
                'group'    => 'alice',
                'content'  => 'Some stuff',
                'source'   => nil,
                'override' => true,
              },
            },
          )
        end

        it 'overrides attributes and removes explicitly unset ones' do
          catalog.create_resource(
            'File',
            {
              'name'   => '/tmp/test',
              'ensure' => 'file',
              'owner'  => 'root',
              'group'  => 'root',
              'source' => 'puppet:///my.server/test',
              'mode'   => '0644',
            },
          )

          resource.autorequire

          result = catalog.resource('File[/tmp/test]')

          expect(result[:owner]).to eq('bob')
          expect(result[:group]).to eq('alice')
          expect(result.parameter(:content).actual_content).to eq('Some stuff')
          expect(result[:mode]).to match(%r{^0?644$})
          expect(result[:source]).to be_nil
        end

        it 'does not pass unset attributes or the override option to created resources' do
          resource.autorequire

          result = catalog.resource('File[/tmp/test]')

          expect(result).not_to be_nil
          expect(result.parameters.keys).not_to include(:source)
          expect(result.parameters.keys).not_to include(:override)
          expect(result[:owner]).to eq('bob')
        end

        it 'fails when override is not a Boolean' do
          expect {
            deferred_resources_type.new(
              name: 'foo',
              resource_type: 'file',
              resources: {
                '/tmp/test' => {
                  'override' => 'please',
                },
              },
            )
          }.to raise_error(%r{The 'override' option on resource '/tmp/test' must be a Boolean})
        end
      end
    end

    context 'when warning' do
      it 'does not add the new resources to the catalog' do
        resource = deferred_resources_type.new(
          name: 'foo',
          resource_type: 'package',
          resources: ['mypackage'],
          mode: 'warning',
          default_options: { 'ensure' => 'absent' },
        )

        # Interpolate the expected options Hash so that the message matches on
        # all Ruby versions (Hash#inspect changed format in Ruby 3.4)
        expected_opts = { ensure: 'absent' }
        expect(Puppet).to receive(:send).with(:warning, "deferred_resources: Would have created Package[mypackage] with #{expected_opts}").once

        resource.autorequire

        expect(catalog.resource('Package', 'mypackage')).to be_nil
      end

      it 'does not override any existing resources' do
        resource = deferred_resources_type.new(
          name: 'foo',
          resource_type: 'file',
          mode: 'warning',
          resources: {
            '/tmp/test' => {
              'ensure'   => 'file',
              'owner'    => 'bob',
              'group'    => 'alice',
              'content'  => 'Some stuff',
              'source'   => nil,
              'override' => true,
            },
          },
        )

        catalog.create_resource(
          'File',
          {
            'name'   => '/tmp/test',
            'ensure' => 'file',
            'owner'  => 'root',
            'group'  => 'root',
            'source' => 'puppet:///my.server/test',
            'mode'   => '0644',
          },
        )

        expected_message = %(deferred_resources: Would have overridden attributes 'ensure', 'owner', 'group', 'content', 'source' on existing resource File[/tmp/test])
        expect(Puppet).to receive(:send).with(:warning, expected_message).once

        resource.autorequire

        result = catalog.resource('File[/tmp/test]')

        expect(result[:owner]).to eq('root')
        expect(result[:group]).to eq('root')
        expect(result[:source]).to eq(['puppet:///my.server/test'])
        expect(result[:content]).to be_nil
        expect(result[:mode]).to match(%r{^0?644$})
      end
    end
  end
end
