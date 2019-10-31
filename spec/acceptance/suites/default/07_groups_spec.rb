require 'spec_helper_acceptance'

test_name 'deferred group resources'

describe 'deferred group resources' do
  let(:manifest) {
    <<-EOS
      group { 'pete_group': ensure => 'present' }
      group { 'sad_panda_group': ensure => 'absent' }

      include 'deferred_resources'
    EOS
  }
  let(:hieradata) {
    <<-EOD
---
deferred_resources::groups::remove:
  - 'oh_the_humanity_group'
  - 'pete_group'
deferred_resources::groups::install:
  - 'sad_panda_group'
  - 'hello_there_group'
    EOD
  }

  let(:hieradata_enforce) {
    <<-EOM
deferred_resources::mode: 'enforcing'
deferred_resources::log_level: 'debug'
    EOM
  }

  hosts.each do |host|
    context "on #{host}" do
      def create_group(host, group)
        on(host, %(puppet resource group #{group} ensure=present))
      end

      context 'with default parameters' do
        it 'should work with no errors' do
          apply_manifest_on(host, manifest, :catch_failures => true)
        end

        it 'should be idempotent' do
          apply_manifest_on(host, manifest, :catch_changes => true)
        end

        it 'should have correct groups installed' do
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
        it 'should create a group to be removed' do
          create_group(host, 'oh_the_humanity_group')
        end

        it 'should set up hieradata' do
          set_hieradata_on(host, hieradata)
        end

        it 'should output messages but not update groups' do
          result = apply_manifest_on(host, manifest, :accept_all_exit_codes => true)

          # groups ignored by deferred_resources because they are already in the catalogue
          ['pete_group','sad_panda_group'].each do |group|
            expect(result.stdout).to match(/Existing resource 'Group\[#{group}\]' .+ has options that differ/m)
          end

          # groups that are only in deferred_resources::groups::remove
          ['oh_the_humanity_group'].each do |group|
             expect(result.stdout).to match(/Would have created Group\[#{group}\] with .*:ensure=>"absent"/m)
          end

          # groups that are only in deferred_resources::groups::install
          ['hello_there_group'].each do |group|
             expect(result.stdout).to match(/Would have created Group\[#{group}\] with.*:ensure=>"present"/m)
          end
        end

        it 'should not have changed the groups installed' do
          # group removed by another catalogue resource
          ['sad_panda_group'].each do |group|
              expect(has_group?(host, group)).to eq false
          end

          # 1 group that would have been removed by deferred_resources and
          # 1 group installed by another catalog resource
          ['oh_the_humanity_group','pete_group'].each do |group|
              expect(has_group?(host, group)).to eq true
          end
        end
      end

      context "with 'enforce' mode, 'debug' log_level, and groups to ensure removed/installed" do
        it 'should create a group to be removed' do
          create_group(host, 'oh_the_humanity_group')
        end

        it 'should set up hieradata' do
          set_hieradata_on(host, hieradata + hieradata_enforce )
        end

        it 'should not output messages when the manifest it applied' do
          result = apply_manifest_on(host, manifest, :accept_all_exit_codes => true)

          # groups ignored by deferred_resources because they are already in the catalogue
          ['pete_group','sad_panda_group'].each do |group|
            expect(result.stdout).not_to match(/Existing resource 'Group\[#{group}\]' .+ has options that differ/m)
          end

          # groups that are only in deferred_resources::groups::remove or
          # deferred_resources::groups::install
          ['oh_the_humanity_group', 'hello_there_group'].each do |group|
             expect(result.stdout).not_to match(/Would have created Group\[#{group}\]/m)
          end
        end

        it 'should have removed and installed groups' do
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
