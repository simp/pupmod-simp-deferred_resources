require 'spec_helper'

package_array = [
  'pkg1',
  'pkg2'
]

package_hash = {
  'pkg3' => {'install_options' => 'stuff'},
  'pkg4' => {}
}

describe 'deferred_resources::packages' do
  shared_examples_for "a structured module" do
    it { is_expected.to compile.with_all_deps }
    it { is_expected.to create_class('deferred_resources') }
    it { is_expected.to contain_class('deferred_resources') }
  end

  context 'supported operating systems' do
    on_supported_os.each do |os, facts|
      context "on #{os}" do
        let(:facts) do
          facts
        end

        context "deferred_resources class without any parameters" do
          let(:params) {{ }}
          it_behaves_like "a structured module"
          it { is_expected.to_not contain_deferred_resources('deferred_resources Package remove')}
          it { is_expected.to_not contain_deferred_resources('deferred_resources Package install')}
        end

        context "with parameters set" do
          let(:params) {{
            'remove'         => package_array,
            'install'        => package_hash,
            'install_ensure' => 'present',
            'mode'           => 'enforcing',
            'log_level'      => 'debug'
          }}

          let(:install_hash){
            hash = params['install']

            hash.each_pair do |rname, opts|
              opts['name'] = rname unless opts['name']
            end
          }

          it { is_expected.to compile.with_all_deps }

          it { is_expected.to contain_deferred_resources('deferred_resources Package remove').with({
            'resource_type'   => 'package',
            'resources'       => params['remove'],
            'mode'            => params['mode'],
            'default_options' => { 'ensure' => 'absent' },
            'log_level'       => params['log_level']
          })}

          it { is_expected.to contain_deferred_resources('deferred_resources Package install').with({
            'resource_type'   => 'package',
            'resources'       => install_hash,
            'mode'            => params['mode'],
            'default_options' => { 'ensure' => params['install_ensure'] },
            'log_level'       => params['log_level']
          })}
        end
      end
    end
  end
end
