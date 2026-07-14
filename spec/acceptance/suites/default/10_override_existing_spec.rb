require 'spec_helper_acceptance'

test_name 'deferred resource overrides'

describe 'deferred resource overrides' do
  let(:manifest) do
    <<~EOS
      file { '/tmp/add_file3': ensure => 'file', content => 'Test Add', mode => '0600' }
      file { '/tmp/add_file4': ensure => 'file', source => 'file:///tmp/source_data', mode => '0600' }

      include 'deferred_resources'
    EOS
  end

  let(:hieradata) do
    <<~EOD
      ---
      deferred_resources::resources:
        file:
          /tmp/add_file2:
            ensure: 'present'
            mode: '0600'
    EOD
  end

  # This is meant to be slapped onto the bottom of 'hieradata'
  #
  # * add_file3 overrides mode and content on the existing catalog resource
  # * add_file4 also unsets 'source' (explicit ~) so that the new 'content'
  #   does not conflict with it
  let(:hieradata_resource_override) do
    <<~EOM
          /tmp/add_file3:
            ensure: 'file'
            mode: '0644'
            content: 'Changed'
            override: true
          /tmp/add_file4:
            ensure: 'file'
            mode: '0644'
            content: 'Changed'
            source: ~
            override: true
      deferred_resources::mode: 'enforcing'
      deferred_resources::log_level: 'debug'
    EOM
  end

  hosts.each do |host|
    context "on #{host}" do
      context 'without overrides enabled' do
        it 'sets up a clean state' do
          on(host, "echo 'junk' > /tmp/source_data")
          set_hieradata_on(host, hieradata)
        end

        it 'works with no errors' do
          apply_manifest_on(host, manifest, catch_failures: true)
        end

        it 'does not have overridden file attributes' do
          file_attrs = YAML.safe_load(
            on(host, 'puppet resource file /tmp/add_file3 --to_yaml').stdout.strip,
          )['file']['/tmp/add_file3']

          expect(file_attrs['mode']).to eq('0600')
        end
      end

      context 'overriding existing resources' do
        it 'sets up override hieradata' do
          set_hieradata_on(host, hieradata + hieradata_resource_override)
        end

        it 'overrides the specified parameters' do
          orig_file_attrs = YAML.safe_load(
            on(host, 'puppet resource file /tmp/add_file3 --to_yaml').stdout.strip,
          )['file']['/tmp/add_file3']

          orig_file_attrs2 = YAML.safe_load(
            on(host, 'puppet resource file /tmp/add_file4 --to_yaml').stdout.strip,
          )['file']['/tmp/add_file4']

          apply_manifest_on(host, manifest, catch_failures: true)

          new_file_attrs = YAML.safe_load(
            on(host, 'puppet resource file /tmp/add_file3 --to_yaml').stdout.strip,
          )['file']['/tmp/add_file3']

          new_file_attrs2 = YAML.safe_load(
            on(host, 'puppet resource file /tmp/add_file4 --to_yaml').stdout.strip,
          )['file']['/tmp/add_file4']

          # Remove things that will have changed
          ['mtime', 'ctime'].each do |attr|
            orig_file_attrs.delete(attr)
            new_file_attrs.delete(attr)
            orig_file_attrs2.delete(attr)
            new_file_attrs2.delete(attr)
          end

          expect(new_file_attrs['mode']).to eq('0644')
          expect(new_file_attrs['content']).not_to eq(orig_file_attrs['content'])
          expect(new_file_attrs2['mode']).to eq('0644')
          expect(new_file_attrs2.key?('source')).to be(false)

          # Remove the things we know changed
          ['mode', 'content'].each do |attr|
            orig_file_attrs.delete(attr)
            new_file_attrs.delete(attr)
            orig_file_attrs2.delete(attr)
            new_file_attrs2.delete(attr)
          end

          # Nothing else should have changed
          expect(orig_file_attrs).to eq(new_file_attrs)
          expect(orig_file_attrs2).to eq(new_file_attrs2)
        end

        it 'is idempotent' do
          apply_manifest_on(host, manifest, catch_changes: true)
        end

        it 'has changed content' do
          result = on(host, 'cat /tmp/add_file4').stdout.strip
          expect(result).to eq('Changed')
        end
      end
    end
  end
end
