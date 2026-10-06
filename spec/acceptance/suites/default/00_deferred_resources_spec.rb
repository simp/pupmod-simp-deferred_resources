require 'spec_helper_acceptance'

test_name 'deferred resources'

describe 'deferred resources' do
  let(:manifest) do
    <<~EOS
      package { 'tmpwatch':  ensure => 'absent'}
      package { 'dos2unix':  ensure => 'installed'}
      user { 'pete': ensure => 'present' }
      user { 'sad_panda': ensure => 'absent' }
      group { 'pete_group': ensure => 'present' }
      group { 'sad_panda_group': ensure => 'absent' }
      file { '/tmp/rm_file2': ensure => 'file', content => 'Test RM' }
      file { '/tmp/add_file1': ensure => 'absent' }

      include 'deferred_resources'
    EOS
  end

  let(:hieradata) do
    <<~EOD
      ---
      deferred_resources::resources:
        package:
          telnet:
            ensure: 'absent'
          dos2unix:
            ensure: 'absent'
          vsftpd:
            ensure: 'absent'
          tmpwatch:
            ensure: 'present'
          zsh:
            ensure: 'present'
        user:
          oh_the_humanity:
            ensure: 'absent'
          pete:
            ensure: 'absent'
          sad_panda:
            ensure: 'present'
          hello_there:
            ensure: 'present'
        group:
          oh_the_humanity_group:
            ensure: 'absent'
          pete_group:
            ensure: 'absent'
          sad_panda_group:
            ensure: 'present'
          hello_there_group:
            ensure: 'present'
        file:
          /tmp/rm_file1:
            ensure: 'absent'
          /tmp/rm_file2:
            ensure: 'absent'
          /tmp/add_file1:
            ensure: 'present'
            mode: '0777'
          /tmp/add_file2:
            ensure: 'present'
            mode: '0600'
    EOD
  end

  let(:hieradata_enforce) do
    <<~EOM
      deferred_resources::mode: 'enforcing'
      deferred_resources::log_level: 'debug'
    EOM
  end

  hosts.each do |host|
    context "on #{host}" do
      context 'with default parameters' do
        it 'works with no errors' do
          install_package host, 'telnet'
          on(host, 'touch /tmp/rm_file1')
          on(host, %(puppet resource user oh_the_humanity ensure=present))
          on(host, %(puppet resource group oh_the_humanity_group ensure=present))

          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end

        it 'has only applied the explicitly declared catalog resources' do
          expect(host.check_for_package('tmpwatch')).to eq false
          expect(host.check_for_package('dos2unix')).to eq true
          expect(has_user?(host, 'pete')).to eq true
          expect(has_user?(host, 'sad_panda')).to eq false
          expect(has_group?(host, 'pete_group')).to eq true
          expect(has_group?(host, 'sad_panda_group')).to eq false
          expect(has_file?(host, '/tmp/rm_file2')).to eq true
          expect(has_file?(host, '/tmp/add_file1')).to eq false
        end
      end

      context "with 'warning' mode and a Hash of resources" do
        it 'sets up hieradata' do
          set_hieradata_on(host, hieradata)
        end

        it 'outputs messages but does not change the system' do
          result = apply_manifest_on(host, manifest, accept_all_exit_codes: true)

          # resources ignored by deferred_resources because they are already
          # in the catalog with different options
          [
            ['Package', 'tmpwatch'],
            ['Package', 'dos2unix'],
            ['User', 'pete'],
            ['User', 'sad_panda'],
            ['Group', 'pete_group'],
            ['Group', 'sad_panda_group'],
            ['File', '/tmp/rm_file2'],
            ['File', '/tmp/add_file1'],
          ].each do |type, title|
            expect(result.stdout).to match(%r{Existing resource '#{type}\[#{title}\]' .+ has options that differ}m)
          end

          # resources that are only in deferred_resources::resources
          [
            ['Package', 'telnet', 'absent'],
            ['Package', 'vsftpd', 'absent'],
            ['Package', 'zsh', 'present'],
            ['User', 'oh_the_humanity', 'absent'],
            ['User', 'hello_there', 'present'],
            ['Group', 'oh_the_humanity_group', 'absent'],
            ['Group', 'hello_there_group', 'present'],
            ['File', '/tmp/rm_file1', 'absent'],
            ['File', '/tmp/add_file2', 'present'],
          ].each do |type, title, ensure_val|
            expect(result.stdout).to match(%r{Would have created #{type}\[#{title}\] with .*#{ensure_val}}m)
          end
        end

        it 'does not have changed the system' do
          expect(host.check_for_package('telnet')).to eq true
          expect(host.check_for_package('vsftpd')).to eq false
          expect(host.check_for_package('zsh')).to eq false
          expect(has_user?(host, 'oh_the_humanity')).to eq true
          expect(has_user?(host, 'hello_there')).to eq false
          expect(has_group?(host, 'oh_the_humanity_group')).to eq true
          expect(has_group?(host, 'hello_there_group')).to eq false
          expect(has_file?(host, '/tmp/rm_file1')).to eq true
          expect(has_file?(host, '/tmp/add_file2')).to eq false
        end
      end

      context "with 'enforcing' mode, 'debug' log_level, and a Hash of resources" do
        it 'sets up hieradata' do
          set_hieradata_on(host, hieradata + hieradata_enforce)
        end

        it 'does not output warning messages when the manifest is applied' do
          result = apply_manifest_on(host, manifest, accept_all_exit_codes: true)

          expect(result.stdout).not_to match(%r{has options that differ}m)
          expect(result.stdout).not_to match(%r{Would have created}m)
        end

        it 'has enforced the deferred resources' do
          # removed or installed by explicitly declared catalog resources,
          # which always win over deferred entries
          expect(host.check_for_package('tmpwatch')).to eq false
          expect(host.check_for_package('dos2unix')).to eq true
          expect(has_user?(host, 'pete')).to eq true
          expect(has_user?(host, 'sad_panda')).to eq false
          expect(has_group?(host, 'pete_group')).to eq true
          expect(has_group?(host, 'sad_panda_group')).to eq false
          expect(has_file?(host, '/tmp/rm_file2')).to eq true
          expect(has_file?(host, '/tmp/add_file1')).to eq false

          # enforced by deferred_resources
          expect(host.check_for_package('telnet')).to eq false
          expect(host.check_for_package('vsftpd')).to eq false
          expect(host.check_for_package('zsh')).to eq true
          expect(has_user?(host, 'oh_the_humanity')).to eq false
          expect(has_user?(host, 'hello_there')).to eq true
          expect(has_group?(host, 'oh_the_humanity_group')).to eq false
          expect(has_group?(host, 'hello_there_group')).to eq true
          expect(has_file?(host, '/tmp/rm_file1')).to eq false
          expect(has_file?(host, '/tmp/add_file2')).to eq true
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end
      end
    end
  end
end
