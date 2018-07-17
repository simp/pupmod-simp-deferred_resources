require 'spec_helper_acceptance'

test_name 'deferred_resources class'

describe 'deferred_resources class' do
  let(:manifest) {
    <<-EOS
      package { 'screen':      ensure => 'absent'}
      package { 'rsh-server':  ensure => 'installed'}

      include 'deferred_resources::packages'
    EOS
  }
  let(:hieradata) {
    <<-EOD
---
deferred_resources::packages::remove:
  'ypserv': ~
  'rsh-server': ~
  'vsftpd': ~
deferred_resources::packages::install:
  - 'screen'
  - 'esc'
  - 'zsh'
deferred_resources::packages::install_ensure: 'present'
    EOD
  }

  let(:hieradata_enforce) {
    <<-EOM
deferred_resources::mode: 'enforcing'
deferred_resources::log_level: 'debug'
    EOM
  }

  context 'on each host' do
    hosts.each do |host|
      context 'with default parameters' do
        it 'should work with no errors' do
          install_package host, 'ypserv'
          apply_manifest_on(host, manifest, :catch_failures => true)
        end

        it 'should be idempotent' do
          apply_manifest_on(host, manifest, :catch_changes => true)
        end

        it 'should have correct packages installed' do
          # package with ensure absent
          ['screen'].each do |pkg|
              expect(host.check_for_package(pkg)).to eq false
          end

          # previously installed package and package with ensure present
          ['ypserv','rsh-server'].each do |pkg|
              expect(host.check_for_package(pkg)).to eq true
          end
        end

      end

      context "with 'warning' mode and packages to ensure removed/installed" do
        it 'should set up hieradata' do
          set_hieradata_on(host, hieradata)
        end

        it 'should output messages but not install or remove packages' do
          install_package host, 'ypserv'
          result = apply_manifest_on(host, manifest, :accept_all_exit_codes => true)

          # packages ignored by deferred_resources because they are already in the catalogue
          ['screen','rsh-server'].each do |pkg|
            expect(result.stdout).to match(/Existing resource 'Package\[#{pkg}\]' .+ has options that differ/m)
          end

          # packages that are only in deferred_resources::packages::remove
          ['vsftpd','ypserv'].each do |pkg|
             expect(result.stdout).to match(/Would have created Package\[#{pkg}\] with .*:ensure=>"absent"/m)
          end

          # packages that are only in deferred_resources::packages::install
          ['esc','zsh'].each do |pkg|
             expect(result.stdout).to match(/Would have created Package\[#{pkg}\] with.*:ensure=>"present"/m)
          end
        end

        it 'should not have changed the packages installed' do
          # package removed by another catalogue resource
          ['screen'].each do |pkg|
              expect(host.check_for_package(pkg)).to eq false
          end

          # 1 package that would have been removed by deferred_resources and
          # 1 package installed by another catalog resource
          ['ypserv','rsh-server'].each do |pkg|
              expect(host.check_for_package(pkg)).to eq true
          end
        end
      end

      context "with 'enforce' mode, 'debug' log_level, and packages to ensure removed/installed" do
        it 'should set up hieradata' do
          set_hieradata_on(host, hieradata + hieradata_enforce )
        end

        it 'should not output messages when the manifest it applied' do
          install_package host, 'ypserv'
          result = apply_manifest_on(host, manifest, :accept_all_exit_codes => true)

          # packages ignored by deferred_resources because they are already in the catalogue
          ['screen','rsh-server'].each do |pkg|
            expect(result.stdout).not_to match(/Existing resource 'Package\[#{pkg}\]' .+ has options that differ/m)
          end

          # packages that are only in deferred_resources::packages::remove or
          # deferred_resources::packages::install
          ['vsftpd','ypserv','esc','zsh'].each do |pkg|
             expect(result.stdout).not_to match(/Would have created Package\[#{pkg}\]/m)
          end
        end

        it 'should have removed and installed packages' do
          # 1st package removed by another catalog resource and 2 remaining packages
          # removed by deferred_resources
          ['screen','ypserv','vsftpd'].each do |pkg|
              expect(host.check_for_package(pkg)).to eq false
          end

          # 1st package installed by another catalog resource and 2 remaining packages
          # removed by deferred_resources
          ['rsh-server','esc', 'zsh'].each do |pkg|
              expect(host.check_for_package(pkg)).to eq true
          end
        end
      end
    end
  end
end

