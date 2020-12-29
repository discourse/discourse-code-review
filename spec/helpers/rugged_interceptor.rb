# frozen_string_literal: true

module RuggedInterceptor
  OriginalRugged = ::Rugged

  module Repository
    OriginalRepository = ::Rugged::Repository

    class << self
      def replacements
        @replacements ||= {}
      end

      def intercept(url, replacement)
        replacements[url] = replacement
      end

      def const_missing(name)
        OriginalRepository.const_get(name)
      end

      def method_missing(method, *args, **kwargs, &blk)
        OriginalRepository.send(method, *args, **kwargs, &blk)
      end

      def clone_at(url, local_path, options = {})
        OriginalRepository.clone_at(replacements.fetch(url), local_path, options)
      end
    end
  end

  class << self
    def const_missing(name)
      OriginalRugged.const_get(name)
    end

    def method_missing(method, *args, **kwargs, &blk)
      OriginalRugged.send(method, *args, **kwargs, &blk)
    end

    def use(&blk)
      begin
        Object.send(:remove_const, :Rugged)
        Object.send(:const_set, :Rugged, RuggedInterceptor)

        blk.call
      ensure
        Object.send(:remove_const, :Rugged)
        Object.send(:const_set, :Rugged, OriginalRugged)
      end
    end
  end
end
