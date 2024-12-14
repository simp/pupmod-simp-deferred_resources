module Acceptance; end
module Acceptance::Helpers; end

module Acceptance::Helpers::ResourceCheckers
  require 'yaml'

  def has_file?(host, file)
    res_info = YAML.safe_load(on(host, %(puppet resource file #{file} --to_yaml)).stdout.strip)

    if res_info
      if res_info['file']
        if res_info['file'][file]
          return res_info['file'][file]['ensure'] == 'file'
        end
      end
    end

    false
  end

  def has_group?(host, group)
    res_info = YAML.safe_load(on(host, %(puppet resource group #{group} --to_yaml)).stdout.strip)
    if res_info
      if res_info['group']
        if res_info['group'][group]
          return res_info['group'][group]['ensure'] == 'present'
        end
      end
    end

    false
  end

  def has_user?(host, user)
    res_info = YAML.safe_load(on(host, %(puppet resource user #{user} --to_yaml)).stdout.strip)
    if res_info
      if res_info['user']
        if res_info['user'][user]
          return res_info['user'][user]['ensure'] == 'present'
        end
      end
    end

    false
  end
end
