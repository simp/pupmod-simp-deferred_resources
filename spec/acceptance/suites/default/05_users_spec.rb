require 'spec_helper_acceptance'

test_name 'deferred user resources'

describe 'deferred user resources' do
  let(:manifest) do
    <<-EOS
      user { 'pete': ensure => 'present' }
      user { 'sad_panda': ensure => 'absent' }

      include 'deferred_resources'
    EOS
  end
  let(:hieradata) do
    <<-EOD
---
deferred_resources::users::remove:
  - 'oh_the_humanity'
  - 'pete'
deferred_resources::users::install:
  - 'sad_panda'
  - 'hello_there'
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
      def create_user(host, user)
        on(host, %(puppet resource user #{user} ensure=present))
      end

      context 'with default parameters' do
        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end

        it 'has correct users installed' do
          # user with ensure absent
          ['sad_panda'].each do |user|
            expect(has_user?(host, user)).to eq false
          end

          # previously installed user with ensure present
          ['pete'].each do |user|
            expect(has_user?(host, user)).to eq true
          end
        end
      end

      context "with 'warning' mode and users to ensure removed/installed" do
        it 'creates a user to be removed' do
          create_user(host, 'oh_the_humanity')
        end

        it 'sets up hieradata' do
          set_hieradata_on(host, hieradata)
        end

        it 'outputs messages but not update users' do
          result = apply_manifest_on(host, manifest, accept_all_exit_codes: true)

          # users ignored by deferred_resources because they are already in the catalogue
          ['pete', 'sad_panda'].each do |user|
            expect(result.stdout).to match(%r{Existing resource 'User\[#{user}\]' .+ has options that differ}m)
          end

          # users that are only in deferred_resources::users::remove
          ['oh_the_humanity'].each do |user|
            expect(result.stdout).to match(%r{Would have created User\[#{user}\] with .*:ensure=>"absent"}m)
          end

          # users that are only in deferred_resources::users::install
          ['hello_there'].each do |user|
            expect(result.stdout).to match(%r{Would have created User\[#{user}\] with.*:ensure=>"present"}m)
          end
        end

        it 'does not have changed the users installed' do
          # user removed by another catalogue resource
          ['sad_panda'].each do |user|
            expect(has_user?(host, user)).to eq false
          end

          # 1 user that would have been removed by deferred_resources and
          # 1 user installed by another catalog resource
          ['oh_the_humanity', 'pete'].each do |user|
            expect(has_user?(host, user)).to eq true
          end
        end
      end

      context "with 'enforce' mode, 'debug' log_level, and users to ensure removed/installed" do
        it 'creates a user to be removed' do
          create_user(host, 'oh_the_humanity')
        end

        it 'sets up hieradata' do
          set_hieradata_on(host, hieradata + hieradata_enforce)
        end

        it 'does not output messages when the manifest it applied' do
          result = apply_manifest_on(host, manifest, accept_all_exit_codes: true)

          # users ignored by deferred_resources because they are already in the catalogue
          ['pete', 'sad_panda'].each do |user|
            expect(result.stdout).not_to match(%r{Existing resource 'User\[#{user}\]' .+ has options that differ}m)
          end

          # users that are only in deferred_resources::users::remove or
          # deferred_resources::users::install
          ['oh_the_humanity', 'hello_there'].each do |user|
            expect(result.stdout).not_to match(%r{Would have created User\[#{user}\]}m)
          end
        end

        it 'has removed and installed users' do
          # 1st user removed by another catalog resource and 1 remaining users
          # removed by deferred_resources
          ['sad_panda', 'oh_the_humanity'].each do |user|
            expect(has_user?(host, user)).to eq false
          end

          # 1st user installed by another catalog resource and 1 remaining users
          # added by deferred_resources
          ['pete', 'hello_there'].each do |user|
            expect(has_user?(host, user)).to eq true
          end
        end
      end
    end
  end
end
