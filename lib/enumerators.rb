# frozen_string_literal: true

module Enumerators
  class MapWithPreviousEnumerator
    include Enumerable

    def initialize(enumerable, &f)
      @enumerable = enumerable
      @f = f
    end

    def each(&blk)
      previous = nil
      first = true

      @enumerable.each do |value|
        unless first
          blk.call(@f.call(previous, value))
        end

        previous = value
        first = false
      end
    end
  end

  class CompactEnumerator
    include Enumerable

    def initialize(enumerable)
      @enumerable = enumerable
    end

    def each(&blk)
      @enumerable.each do |value|
        unless value.nil?
          blk.call(value)
        end
      end
    end
  end

  class MapEnumerator
    include Enumerable

    def initialize(enumerable, &f)
      @enumerable = enumerable
      @f = f
    end

    def each(&blk)
      @enumerable.each do |value|
        blk.call(@f.call(value))
      end
    end
  end

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
