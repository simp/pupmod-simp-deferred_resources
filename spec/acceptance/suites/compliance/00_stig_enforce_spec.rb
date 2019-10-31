require 'spec_helper_acceptance'

test_name 'deferred_resources class STIG'

describe 'deferred_resources class STIG' do
  let(:manifest) {
    <<-EOS
      include 'deferred_resources'
    EOS
  }

  let(:hieradata){ <<-EOM
---
compliance_markup::enforcement:
  - disa_stig
    EOM
  }

  hosts.each do |host|
    context "on #{host}" do
      let(:hiera_yaml){ <<-EOM
---
version: 5
hierarchy:
  - name: Common
    path: common.yaml
  - name: Compliance
    lookup_key: compliance_markup::enforcement
defaults:
  data_hash: yaml_data
  datadir: "#{hiera_datadir(host)}"
        EOM
      }

      it 'should work with no errors' do
        create_remote_file(host, host.puppet['hiera_config'], hiera_yaml)
        write_hieradata_to(host, hieradata)

        apply_manifest_on(host, manifest, :catch_failures => true)
      end

      it 'should be idempotent' do
        apply_manifest_on(host, manifest, :catch_changes => true)
      end

      [ 'ftp', 'games'].each do |id|
        it "should remove '#{id}' user" do
          expect( has_user?(host, id) ).to eq false
        end

        it "should remove '#{id}' group" do
          expect( has_group?(host, id) ).to eq false
        end
      end
    end
  end
end
