require 'spec_helper'

package_array = [
  'pkg1',
  'pkg2'
]

package_hash = {
  'pkg3' => {'install_options' => 'stuff'},
  'pkg4' => {}
}

describe 'deferred_resources' do
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
          it { is_expected.to_not contain_deferred_packages('compliance packages remove')}
          it { is_expected.to_not contain_deferred_packages('compliance packages install')}
        end

        context "with parameters set" do
          let(:params) {{
            'packages_remove'  => package_array,
            'packages_install' => package_hash,
            'mode'             => 'enforcing',
            'package_ensure'   => 'present',
            'enable_warnings'  => false
          }}
          it { is_expected.to compile.with_all_deps }
          it { is_expected.to contain_deferred_packages('compliance packages remove').with({
            'packages' => package_array,
            'mode' => 'enforcing',
            'warning' => :false,
            'default_options' => { 'ensure'  => 'absent' }
          })}
          it { is_expected.to contain_deferred_packages('compliance packages install').with({
            'packages' => package_hash,
            'mode' => 'enforcing',
            'default_options' => { 'ensure'  => 'present' },
            'warning' => :false
          })}
          it do
            skip('This is commented out because the packages are created with create_resource in ruby code and I have not figured out how to test that.  The acceptance test does test this.')
            is_expected.to contain_package('pkg1').with_ensure('absent')
            is_expected.to contain_package('pkg3').with_ensure('present')
            content = catalogue.resources
            expect(content).to include('absent')
          end

        end
      end
    end
  end

end
