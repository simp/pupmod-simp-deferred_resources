require 'spec_helper_acceptance'

test_name 'deferred file resources'

describe 'deferred file resources' do
  let(:manifest) {
    <<-EOS
      file { '/tmp/rm_file2': ensure => 'file', content => 'Test RM' }
      file { '/tmp/add_file1': ensure => 'absent' }
      file { '/tmp/add_file3': ensure => 'file', content => 'Test Add', mode => '0600' }
      file { '/tmp/add_file4': ensure => 'file', source => 'file:///tmp/source_data', mode => '0600' }

      include 'deferred_resources'
    EOS
  }
  let(:hieradata) {
    <<-EOD
---
deferred_resources::files::remove:
  - '/tmp/rm_file1'
  - '/tmp/rm_file2'
deferred_resources::files::install:
  '/tmp/add_file1':
    'mode': '0777'
  '/tmp/add_file2':
    'mode': '0600'
    EOD
  }

  let(:hieradata_enforce) {
    <<-EOM
deferred_resources::mode: 'enforcing'
deferred_resources::log_level: 'debug'
    EOM
  }

  # This is meant to be slapped onto the bottom of 'hieradata'
  let(:hieradata_resource_override) {
    <<-EOM
  '/tmp/add_file3':
    'mode': '0644'
    'content': 'Changed'
  '/tmp/add_file4':
    'mode': '0644'
    'content': 'Changed'
    'seltype': 'system_map_t'
deferred_resources::mode: 'enforcing'
deferred_resources::log_level: 'debug'
deferred_resources::files::update_existing_resources: true
    EOM
  }

  hosts.each do |host|
    context "on #{host}" do
      def has_file?(host, file)
        res_info = YAML.safe_load(on(host, %(puppet resource file #{file} --to_yaml)).output)

        if res_info
          if res_info['file']
            if res_info['file'][file]
              return res_info['file'][file]['ensure'] == 'file'
            end
          end
        end

        return false
      end

      context 'with default parameters' do
        it 'should work with no errors' do
          on(host, "echo \'junk\' > /tmp/source_data")
          apply_manifest_on(host, manifest, :catch_failures => true)
        end

        it 'should be idempotent' do
          apply_manifest_on(host, manifest, :catch_changes => true)
        end

        it 'should have correct files installed' do
          # file with ensure absent
          ['/tmp/add_file1'].each do |file|
              expect(has_file?(host, file)).to eq false
          end

          # previously installed file with ensure present
          ['/tmp/rm_file2'].each do |file|
              expect(has_file?(host, file)).to eq true
          end
        end
      end

      context "with 'warning' mode and files to ensure removed/installed" do
        it 'should create a file to be removed' do
          on(host, 'touch /tmp/rm_file1')
        end

        it 'should set up hieradata' do
          set_hieradata_on(host, hieradata)
        end

        it 'should output messages but not update files' do
          result = apply_manifest_on(host, manifest, :accept_all_exit_codes => true)

          # files ignored by deferred_resources because they are already in the catalogue
          ['/tmp/rm_file2','/tmp/add_file1'].each do |file|
            expect(result.stdout).to match(/Existing resource 'File\[#{file}\]' .+ has options that differ/m)
          end

          # files that are only in deferred_resources::files::remove
          ['/tmp/rm_file1'].each do |file|
             expect(result.stdout).to match(/Would have created File\[#{file}\] with .*:ensure=>"absent"/m)
          end

          # files that are only in deferred_resources::files::install
          ['/tmp/add_file2'].each do |file|
             expect(result.stdout).to match(/Would have created File\[#{file}\] with.*:ensure=>"present"/m)
          end
        end

        it 'should not have changed the files installed' do
          # file removed by another catalogue resource
          ['/tmp/add_file1'].each do |file|
              expect(has_file?(host, file)).to eq false
          end

          # 1 file that would have been removed by deferred_resources and
          # 1 file installed by another catalog resource
          ['/tmp/rm_file1','/tmp/rm_file2'].each do |file|
              expect(has_file?(host, file)).to eq true
          end
        end

      end

      context "with 'enforce' mode, 'debug' log_level, and files to ensure removed/installed" do
        it 'should create a file to be removed' do
          on(host, 'touch /tmp/rm_file1')
        end

        it 'should set up hieradata' do
          set_hieradata_on(host, hieradata + hieradata_enforce )
        end

        it 'should not output messages when the manifest it applied' do
          result = apply_manifest_on(host, manifest, :accept_all_exit_codes => true)

          # files ignored by deferred_resources because they are already in the catalogue
          ['/tmp/rm_file2','/tmp/add_file1'].each do |file|
            expect(result.stdout).not_to match(/Existing resource 'File\[#{file}\]' .+ has options that differ/m)
          end

          # files that are only in deferred_resources::files::remove or
          # deferred_resources::files::install
          ['/tmp/rm_file1', '/tmp/add_file2'].each do |file|
             expect(result.stdout).not_to match(/Would have created File\[#{file}\]/m)
          end
        end

        it 'should have removed and installed files' do
          # 1st file removed by another catalog resource and 1 remaining files
          # removed by deferred_resources
          ['/tmp/add_file1', '/tmp/rm_file1'].each do |file|
              expect(has_file?(host, file)).to eq false
          end

          # 1st file installed by another catalog resource and 1 remaining files
          # added by deferred_resources
          ['/tmp/rm_file2', '/tmp/add_file2'].each do |file|
              expect(has_file?(host, file)).to eq true
          end
        end

        it 'should not have overridden file attributes' do
          file_attrs = YAML.load(
            on(host, 'puppet resource file /tmp/add_file2 --to_yaml').output.strip
          )['file']['/tmp/add_file2']

          expect(file_attrs['mode']).to eq('0600')
        end
      end

      context 'overriding existing resources' do
        it 'should set up a clean state' do
          set_hieradata_on(host, hieradata)
        end

        it 'should work with no errors' do
          apply_manifest_on(host, manifest, :catch_failures => true)
        end

        it 'should set up override hieradata' do
          set_hieradata_on(host, hieradata + hieradata_resource_override)
        end

        it 'should override selected parameters' do
          orig_file_attrs = YAML.load(
            on(host, 'puppet resource file /tmp/add_file3 --to_yaml').output.strip
          )['file']['/tmp/add_file3']

          orig_file_attrs2 = YAML.load(
            on(host, 'puppet resource file /tmp/add_file4 --to_yaml').output.strip
          )['file']['/tmp/add_file4']


          apply_manifest_on(host, manifest, :catch_failures => true)

          new_file_attrs = YAML.load(
            on(host, 'puppet resource file /tmp/add_file3 --to_yaml').output.strip
          )['file']['/tmp/add_file3']

          new_file_attrs2 = YAML.load(
            on(host, 'puppet resource file /tmp/add_file4 --to_yaml').output.strip
          )['file']['/tmp/add_file4']

          # Remove things that will have changed
          ['mtime','ctime'].each do |attr|
            orig_file_attrs.delete(attr)
            new_file_attrs.delete(attr)
            orig_file_attrs2.delete(attr)
            new_file_attrs2.delete(attr)
          end

          expect(new_file_attrs['mode']).to eq('0644')
          expect(new_file_attrs['content']).to_not eq(orig_file_attrs['content'])
          expect(new_file_attrs2.has_key?('source')).to be(false)

          # Remove the things we know changed
          ['mode','content'].each do |attr|
            orig_file_attrs.delete(attr)
            new_file_attrs.delete(attr)
            orig_file_attrs2.delete(attr)
            new_file_attrs2.delete(attr)
          end

          # Nothing else should have changed
          expect(orig_file_attrs).to eq(new_file_attrs)
          # nothing else should have changed, even seltype because it is not
          # in the override list.
          expect(orig_file_attrs2).to eq(new_file_attrs2)
        end

        it 'should be idempotent' do
          apply_manifest_on(host, manifest, :catch_changes => true)
        end

        it 'should  have changed content' do
          result = on(host,'cat /tmp/add_file4').stdout.strip
          expect(result).to eq('Changed')
        end
      end
    end
  end
end
