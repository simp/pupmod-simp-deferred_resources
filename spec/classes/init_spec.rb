require 'spec_helper'

describe 'deferred_resources' do
  # Parameter input for rspec-puppet (:undef becomes a Puppet undef)
  let(:resources) do
    {
      'package' => {
        'pkg1' => { 'ensure' => 'absent' },
        'pkg2' => :undef,
        'pkg3' => { 'ensure' => 'installed', 'install_options' => 'stuff' },
      },
      'user' => {
        'user1' => { 'ensure' => 'absent' },
      },
      'file' => {
        '/tmp/file1' => { 'ensure' => 'present', 'owner' => 'bob' },
      },
    }
  end

  # The same structure as it appears in the compiled catalog after the
  # native type has munged it (a 'name' is added and empty entries become
  # empty Hashes)
  let(:expected_resources) do
    {
      'package' => {
        'pkg1' => { 'ensure' => 'absent', 'name' => 'pkg1' },
        'pkg2' => { 'name' => 'pkg2' },
        'pkg3' => { 'ensure' => 'installed', 'install_options' => 'stuff', 'name' => 'pkg3' },
      },
      'user' => {
        'user1' => { 'ensure' => 'absent', 'name' => 'user1' },
      },
      'file' => {
        '/tmp/file1' => { 'ensure' => 'present', 'owner' => 'bob', 'name' => '/tmp/file1' },
      },
    }
  end

  context 'supported operating systems' do
    on_supported_os.each do |os, os_facts|
      context "on #{os}" do
        let(:facts) { os_facts }

        context 'without any parameters' do
          let(:params) { {} }

          it { is_expected.to compile.with_all_deps }
          it { is_expected.not_to contain_deferred_resources('deferred_resources package') }
        end

        context 'with a mixed Hash of resources' do
          let(:params) do
            {
              'resources' => resources,
              'mode'      => 'enforcing',
              'log_level' => 'debug',
            }
          end

          it { is_expected.to compile.with_all_deps }

          it {
            is_expected.to contain_deferred_resources('deferred_resources package').with(
              'resource_type'   => 'package',
              'resources'       => expected_resources['package'],
              'default_options' => {},
              'mode'            => 'enforcing',
              'log_level'       => 'debug',
            )
          }

          it {
            is_expected.to contain_deferred_resources('deferred_resources user').with(
              'resource_type' => 'user',
              'resources'     => expected_resources['user'],
            )
          }

          it {
            is_expected.to contain_deferred_resources('deferred_resources file').with(
              'resource_type' => 'file',
              'resources'     => expected_resources['file'],
            )
          }
        end

        context 'with default parameters' do
          let(:params) { { 'resources' => resources } }

          it { is_expected.to compile.with_all_deps }

          it {
            is_expected.to contain_deferred_resources('deferred_resources package').with(
              'mode'      => 'warning',
              'log_level' => 'info',
            )
          }
        end

        context 'with mixed-case resource type names' do
          let(:params) do
            {
              'resources' => { 'Package' => { 'pkg1' => { 'ensure' => 'absent' } } },
            }
          end

          it { is_expected.to compile.with_all_deps }
          it { is_expected.to contain_deferred_resources('deferred_resources package').with('resource_type' => 'package') }
        end

        context 'with default_options' do
          let(:params) do
            {
              'resources'       => resources,
              'default_options' => {
                'Package' => { 'ensure' => 'installed' },
              },
            }
          end

          it { is_expected.to compile.with_all_deps }

          it {
            is_expected.to contain_deferred_resources('deferred_resources package').with(
              'default_options' => { 'ensure' => 'installed' },
            )
          }

          it {
            is_expected.to contain_deferred_resources('deferred_resources user').with(
              'default_options' => {},
            )
          }
        end

        context 'with per-resource overrides' do
          let(:params) do
            {
              'resources' => {
                'file' => {
                  '/tmp/file1' => {
                    'ensure'   => 'file',
                    'content'  => 'stuff',
                    'source'   => :undef,
                    'override' => true,
                  },
                  '/tmp/file2' => {
                    'ensure' => 'file',
                  },
                },
              },
            }
          end

          it { is_expected.to compile.with_all_deps }

          it {
            is_expected.to contain_deferred_resources('deferred_resources file').with(
              'resources' => {
                '/tmp/file1' => {
                  'ensure'   => 'file',
                  'content'  => 'stuff',
                  'source'   => nil,
                  'override' => true,
                  'name'     => '/tmp/file1',
                },
                '/tmp/file2' => {
                  'ensure' => 'file',
                  'name'   => '/tmp/file2',
                },
              },
            )
          }
        end

        context 'with a non-Boolean override option' do
          let(:params) do
            {
              'resources' => {
                'package' => {
                  'pkg1' => { 'override' => 'please' },
                },
              },
            }
          end

          it {
            is_expected.to compile.and_raise_error(%r{The 'override' option on package resource 'pkg1' must be a Boolean})
          }
        end

        context 'with a non-Boolean override option in default_options' do
          let(:params) do
            {
              'resources'       => { 'package' => { 'pkg1' => :undef } },
              'default_options' => { 'package' => { 'override' => 'yes' } },
            }
          end

          it {
            is_expected.to compile.and_raise_error(%r{The 'override' option in \$default_options for resource type 'package' must be a Boolean})
          }
        end

        context 'with a resource type that has no entries' do
          let(:params) do
            {
              'resources' => { 'package' => {} },
            }
          end

          it { is_expected.to compile.with_all_deps }
          it { is_expected.not_to contain_deferred_resources('deferred_resources package') }
        end

        context 'with the same resource type passed in different cases' do
          let(:params) do
            {
              'resources' => {
                'package' => { 'pkg1' => :undef },
                'Package' => { 'pkg2' => :undef },
              },
            }
          end

          it {
            is_expected.to compile.and_raise_error(%r{Resource type 'package' was passed to \$resources more than once})
          }
        end

        context 'with two entries referencing the same resource via the name attribute' do
          let(:params) do
            {
              'resources' => {
                'package' => {
                  'pkg1'     => { 'ensure' => 'installed' },
                  'orphaned' => { 'name' => 'pkg1', 'ensure' => 'absent' },
                },
              },
            }
          end

          it {
            is_expected.to compile.and_raise_error(%r{package resources were specified multiple times via their title or 'name' attribute: 'pkg1'})
          }
        end
      end
    end
  end
end
