# frozen_string_literal: true

module TypedData
  module TypedStruct
    def self.new(base=Object, **attributes, &blk)
      ordered_attribute_keys = attributes.keys.sort

      Class.new(base) do
        attr_reader *attributes.keys

        define_method(:initialize) do |**opts|
          attributes.each do |attr_name, attr_type|
            value = opts.fetch(attr_name)

            unless attr_type === value
              raise TypeError, "Expected #{attr_name} to be of type #{attr_type}, got #{value.class}"
            end

            instance_variable_set(:"@#{attr_name}", value.freeze)
          end
        end

        define_method(:hash) do
          ordered_attribute_keys.map { |key| send(key) }.hash
        end

        define_method(:eql?) do |other|
          return false unless self.class == other.class

          ordered_attribute_keys.all? do |key|
            send(key).eql?(other.send(key))
          end
        end

        alias_method(:==, :eql?)

        instance_eval(&blk) if blk
      end
    end
  end

  module TypedTaggedUnion
    def self.new(**alternatives)
      base =
        Class.new do
          define_singleton_method(:create) do |name, **attributes|
            const_get(name.to_s.camelize.to_sym).new(**attributes)
          end
        end

      alternatives.each do |tag, attributes|
        alternative_klass =
          TypedStruct.new(base, **attributes) do
            define_singleton_method(:tag) do
              tag
            end
          end

        base.const_set(
          tag.to_s.camelize.to_sym,
          alternative_klass
        )
      end

      base
    end
  end

  class Boolean
    def ===(other)
      TrueClass === other || FalseClass === other
    end
  end

  module OrNil
    def self.[](klass)
      Class.new do
        define_singleton_method(:===) do |other|
          other.nil? || klass === other
        end
      end
    end
  end
end
