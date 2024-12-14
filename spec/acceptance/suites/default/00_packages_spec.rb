require 'spec_helper_acceptance'

test_name 'deferred package resources'

describe 'deferred package resources' do
  let(:manifest) do
    <<-EOS
      package { 'tmpwatch':  ensure => 'absent'}
      package { 'dos2unix':  ensure => 'installed'}

      include 'deferred_resources'
    EOS
  end
  let(:hieradata) do
    <<-EOD
---
deferred_resources::packages::remove:
  'ypserv': ~
  'dos2unix': ~
  'vsftpd': ~
deferred_resources::packages::install:
  - 'tmpwatch'
  - 'zsh'
deferred_resources::packages::install_ensure: 'present'
    EOD
  end

  let(:hieradata_enforce) do
    <<-EOM
deferred_resources::mode: 'enforcing'
deferred_resources::log_level: 'debug'
    EOM
  end

  context 'on each host' do
    hosts.each do |host|
      context 'with default parameters' do
        it 'works with no errors' do
          install_package host, 'ypserv'
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end

        it 'has correct packages installed' do
          # package with ensure absent
          ['tmpwatch'].each do |pkg|
            expect(host.check_for_package(pkg)).to eq false
          end

          # previously installed package and package with ensure present
          ['ypserv', 'dos2unix'].each do |pkg|
            expect(host.check_for_package(pkg)).to eq true
          end
        end
      end

      context "with 'warning' mode and packages to ensure removed/installed" do
        it 'sets up hieradata' do
          set_hieradata_on(host, hieradata)
        end

        it 'outputs messages but not install or remove packages' do
          install_package host, 'ypserv'
          result = apply_manifest_on(host, manifest, accept_all_exit_codes: true)

          # packages ignored by deferred_resources because they are already in the catalogue
          ['tmpwatch', 'dos2unix'].each do |pkg|
            expect(result.stdout).to match(%r{Existing resource 'Package\[#{pkg}\]' .+ has options that differ}m)
          end

          # packages that are only in deferred_resources::packages::remove
          ['vsftpd', 'ypserv'].each do |pkg|
            expect(result.stdout).to match(%r{Would have created Package\[#{pkg}\] with .*:ensure=>"absent"}m)
          end

          # packages that are only in deferred_resources::packages::install
          ['zsh'].each do |pkg|
            expect(result.stdout).to match(%r{Would have created Package\[#{pkg}\] with.*:ensure=>"present"}m)
          end
        end

        it 'does not have changed the packages installed' do
          # package removed by another catalogue resource
          ['tmpwatch'].each do |pkg|
            expect(host.check_for_package(pkg)).to eq false
          end

          # 1 package that would have been removed by deferred_resources and
          # 1 package installed by another catalog resource
          ['ypserv', 'dos2unix'].each do |pkg|
            expect(host.check_for_package(pkg)).to eq true
          end
        end
      end

      context "with 'enforce' mode, 'debug' log_level, and packages to ensure removed/installed" do
        it 'sets up hieradata' do
          set_hieradata_on(host, hieradata + hieradata_enforce)
        end

        it 'does not output messages when the manifest it applied' do
          install_package host, 'ypserv'
          result = apply_manifest_on(host, manifest, accept_all_exit_codes: true)

          # packages ignored by deferred_resources because they are already in the catalogue
          ['tmpwatch', 'dos2unix'].each do |pkg|
            expect(result.stdout).not_to match(%r{Existing resource 'Package\[#{pkg}\]' .+ has options that differ}m)
          end

          # packages that are only in deferred_resources::packages::remove or
          # deferred_resources::packages::install
          ['vsftpd', 'ypserv', 'zsh'].each do |pkg|
            expect(result.stdout).not_to match(%r{Would have created Package\[#{pkg}\]}m)
          end
        end

        it 'has removed and installed packages' do
          # 1st package removed by another catalog resource and 2 remaining packages
          # removed by deferred_resources
          ['tmpwatch', 'ypserv', 'vsftpd'].each do |pkg|
            expect(host.check_for_package(pkg)).to eq false
          end

          # 1st package installed by another catalog resource and 2 remaining packages
          # removed by deferred_resources
          ['dos2unix', 'zsh'].each do |pkg|
            expect(host.check_for_package(pkg)).to eq true
          end
        end
      end
    end
  end
end
