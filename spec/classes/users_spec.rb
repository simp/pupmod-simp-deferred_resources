require 'spec_helper'

user_array = [
  'user1',
  'user2',
]

user_hash = {
  'user3' => {}
}

describe 'deferred_resources::users' do
  shared_examples_for 'a structured module' do
    it { is_expected.to compile.with_all_deps }
    it { is_expected.to create_class('deferred_resources') }
  end

  context 'supported operating systems' do
    on_supported_os.each do |os, facts|
      context "on #{os}" do
        let(:facts) do
          facts
        end

        context 'deferred_resources class without any parameters' do
          let(:params) { {} }

          it_behaves_like 'a structured module'
          it { is_expected.not_to contain_deferred_resources('deferred_resources User remove') }
          it { is_expected.not_to contain_deferred_resources('deferred_resources User install') }
        end

        context 'with parameters set' do
          let(:params) do
            {
              'remove' => user_array,
           'install'   => user_hash,
           'mode'      => 'enforcing',
           'log_level' => 'debug'
            }
          end

          let(:install_hash) do
            hash = params['install']

            hash.each_pair do |rname, opts|
              opts['name'] = rname unless opts['name']
            end
          end

          it { is_expected.to compile.with_all_deps }

          it {
            is_expected.to contain_deferred_resources('deferred_resources User remove').with({
                                                                                               'resource_type' => 'user',
            'resources'       => params['remove'],
            'mode'            => params['mode'],
            'default_options' => { 'ensure' => 'absent' },
            'log_level'       => params['log_level']
                                                                                             })
          }

          it {
            is_expected.to contain_deferred_resources('deferred_resources User install').with({
                                                                                                'resource_type' => 'user',
            'resources'       => install_hash,
            'mode'            => params['mode'],
            'default_options' => { 'ensure' => 'present' },
            'log_level'       => params['log_level']
                                                                                              })
          }
        end
      end
    end
  end
end
