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
          ['screen'].each do |pkg|
              expect(host.check_for_package(pkg)).to be === false
          end
          ['ypserv','rsh-server'].each do |pkg|
              expect(host.check_for_package(pkg)).to be === true
          end
        end

      end

      context 'with mode set to warning and enable warnings set to false' do
        it 'should set up hieradata' do
          set_hieradata_on(host, hieradata)
        end

        it 'should output messages but not install or remove packages' do
          install_package host, 'ypserv'
          result = apply_manifest_on(host, manifest, :accept_all_exit_codes => true)
          ['screen','rsh-server'].each do |pkg|
            expect(result.stdout).to match(/Existing resource 'Package\[#{pkg}\]' .+ has options that differ/m)
          end
          ['vsftpd','ypserv'].each do |pkg|
             expect(result.stdout).to match(/Would have created Package\[#{pkg}\]/m)
          end
          ['esc','zsh'].each do |pkg|
             expect(result.stdout).to match(/Would have created Package\[#{pkg}\]/m)
          end
        end
        it 'should  not have changed the packages installed' do
          ['screen'].each do |pkg|
              expect(host.check_for_package(pkg)).to be === false
          end
          ['ypserv','rsh-server'].each do |pkg|
              expect(host.check_for_package(pkg)).to be === true
          end
        end
      end
      context 'with mode set to enforce ' do
        it 'should set up hieradata' do
          set_hieradata_on(host, hieradata + hieradata_enforce )
        end

        it 'should not output messages when the manifest it applied' do
          install_package host, 'ypserv'
          result = apply_manifest_on(host, manifest, :accept_all_exit_codes => true)
          ['screen','rsh-server'].each do |pkg|
            expect(result.stdout).not_to match(/Existing resource 'Package\[#{pkg}\]' .+ has options that differ/m)
          end
          ['vsftpd','ypserv','esc','zsh'].each do |pkg|
             expect(result.stdout).not_to match(/Would have created Package\[#{pkg}\]/m)
          end
        end

        it 'should have removed and installed packages' do
          ['screen','ypserv','vsftpd'].each do |pkg|
              expect(host.check_for_package(pkg)).to be === false
          end
          ['zsh','rsh-server','esc'].each do |pkg|
              expect(host.check_for_package(pkg)).to be === true
          end
        end
      end
    end
  end
end

