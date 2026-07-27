module Aicoo
  module Lovable
    module GithubRepositoryIdentity
      module_function

      def normalize(value)
        text = value.to_s.strip.delete_suffix(".git")
        text = text.sub(%r{\Ahttps?://github\.com/}i, "").sub(%r{\Agit@github\.com:}i, "")
        parts = text.split(/[\/?#]/).reject(&:blank?)
        return if parts.size < 2

        "#{parts[0]}/#{parts[1]}".downcase
      end
    end
  end
end
