require 'spec_helper_acceptance'

test_name 'deferred_resources class STIG'

describe 'deferred_resources class STIG' do
  let(:manifest) do
    <<~EOS
      include 'deferred_resources'
    EOS
  end

  # A STIG-like enforcement policy expressed through the module's Hiera API
  let(:hieradata) do
    <<~EOM
      ---
      deferred_resources::mode: 'enforcing'
      deferred_resources::resources:
        package:
          telnet-server:
            ensure: 'absent'
          vsftpd:
            ensure: 'absent'
        user:
          ftp:
            ensure: 'absent'
          games:
            ensure: 'absent'
        group:
          ftp:
            ensure: 'absent'
          games:
            ensure: 'absent'
    EOM
  end

  hosts.each do |host|
    context "on #{host}" do
      it 'works with no errors' do
        set_hieradata_on(host, hieradata)

        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      [ 'ftp', 'games'].each do |id|
        it "removes '#{id}' user" do
          expect(has_user?(host, id)).to eq false
        end

        it "removes '#{id}' group" do
          expect(has_group?(host, id)).to eq false
        end
      end
    end
  end
end
