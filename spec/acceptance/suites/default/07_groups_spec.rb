require 'spec_helper_acceptance'

test_name 'deferred group resources'

describe 'deferred group resources' do
  let(:manifest) do
    <<-EOS
      group { 'pete_group': ensure => 'present' }
      group { 'sad_panda_group': ensure => 'absent' }

      include 'deferred_resources'
    EOS
  end
  let(:hieradata) do
    <<-EOD
---
deferred_resources::groups::remove:
  - 'oh_the_humanity_group'
  - 'pete_group'
deferred_resources::groups::install:
  - 'sad_panda_group'
  - 'hello_there_group'
    EOD
  end

  let(:hieradata_enforce) do
    <<-EOM
deferred_resources::mode: 'enforcing'
deferred_resources::log_level: 'debug'
    EOM
  end

  hosts.each do |host|
    context "on #{host}" do
      def create_group(host, group)
        on(host, %(puppet resource group #{group} ensure=present))
      end

      context 'with default parameters' do
        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end

        it 'has correct groups installed' do
          # group with ensure absent
          ['sad_panda_group'].each do |group|
            expect(has_group?(host, group)).to eq false
          end

          # previously installed group with ensure present
          ['pete_group'].each do |group|
            expect(has_group?(host, group)).to eq true
          end
        end
      end

      context "with 'warning' mode and groups to ensure removed/installed" do
        it 'creates a group to be removed' do
          create_group(host, 'oh_the_humanity_group')
        end

        it 'sets up hieradata' do
          set_hieradata_on(host, hieradata)
        end

        it 'outputs messages but not update groups' do
          result = apply_manifest_on(host, manifest, accept_all_exit_codes: true)

          # groups ignored by deferred_resources because they are already in the catalogue
          ['pete_group', 'sad_panda_group'].each do |group|
            expect(result.stdout).to match(%r{Existing resource 'Group\[#{group}\]' .+ has options that differ}m)
          end

          # groups that are only in deferred_resources::groups::remove
          ['oh_the_humanity_group'].each do |group|
            expect(result.stdout).to match(%r{Would have created Group\[#{group}\] with .*:ensure=>"absent"}m)
          end

          # groups that are only in deferred_resources::groups::install
          ['hello_there_group'].each do |group|
            expect(result.stdout).to match(%r{Would have created Group\[#{group}\] with.*:ensure=>"present"}m)
          end
        end

        it 'does not have changed the groups installed' do
          # group removed by another catalogue resource
          ['sad_panda_group'].each do |group|
            expect(has_group?(host, group)).to eq false
          end

          # 1 group that would have been removed by deferred_resources and
          # 1 group installed by another catalog resource
          ['oh_the_humanity_group', 'pete_group'].each do |group|
            expect(has_group?(host, group)).to eq true
          end
        end
      end

      context "with 'enforce' mode, 'debug' log_level, and groups to ensure removed/installed" do
        it 'creates a group to be removed' do
          create_group(host, 'oh_the_humanity_group')
        end

        it 'sets up hieradata' do
          set_hieradata_on(host, hieradata + hieradata_enforce)
        end

        it 'does not output messages when the manifest it applied' do
          result = apply_manifest_on(host, manifest, accept_all_exit_codes: true)

          # groups ignored by deferred_resources because they are already in the catalogue
          ['pete_group', 'sad_panda_group'].each do |group|
            expect(result.stdout).not_to match(%r{Existing resource 'Group\[#{group}\]' .+ has options that differ}m)
          end

          # groups that are only in deferred_resources::groups::remove or
          # deferred_resources::groups::install
          ['oh_the_humanity_group', 'hello_there_group'].each do |group|
            expect(result.stdout).not_to match(%r{Would have created Group\[#{group}\]}m)
          end
        end

        it 'has removed and installed groups' do
          # 1st group removed by another catalog resource and 1 remaining groups
          # removed by deferred_resources
          ['sad_panda_group', 'oh_the_humanity_group'].each do |group|
            expect(has_group?(host, group)).to eq false
          end

          # 1st group installed by another catalog resource and 1 remaining groups
          # added by deferred_resources
          ['pete_group', 'hello_there_group'].each do |group|
            expect(has_group?(host, group)).to eq true
          end
        end
      end
    end
  end
end
