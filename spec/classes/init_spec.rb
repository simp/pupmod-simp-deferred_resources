require 'spec_helper'

describe 'deferred_resources' do
  context 'supported operating systems' do
    on_supported_os.each do |os, os_facts|
      context "on #{os}" do
        let(:facts) do
          os_facts
        end

        it { is_expected.to compile.with_all_deps }
      end
    end
  end
end
