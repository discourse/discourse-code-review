# frozen_string_literal: true

module Enumerators
  class FlattenMerge
    include Enumerable

    def initialize(enumerables, &compare)
      @enumerables = enumerables
      @compare = compare
    end

    def each(&blk)
      enumerators =
        @enumerables
          .map(&:to_enum)
          .select { |enumerator|
            begin
              enumerator.peek
              true
            rescue StopIteration
              false
            end
          }

      queue =
        PQueue.new(enumerators) do |a, b|
          @compare.call(a.peek, b.peek)
        end

      until queue.empty?
        enumerator = queue.pop
        blk.call(enumerator.next)

        begin
          enumerator.peek
        rescue StopIteration
        else
          queue.push(enumerator)
        end
      end
    end
  end
end
