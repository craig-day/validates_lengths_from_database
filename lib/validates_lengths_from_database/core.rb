module ValidatesLengthsFromDatabase
  def self.included(base)
    base.send(:extend, ClassMethods)
    base.send(:include, InstanceMethods)
  end

  class UnicodeLengthValidator < ActiveModel::Validations::LengthValidator
    def validate_each(record, attribute, value)
      value_for_validation = value.is_a?(String) ? value.bytes : value

      super(record, attribute, value_for_validation)
    end
  end

  module ClassMethods
    def validates_lengths_from_database(options = {})
      options.symbolize_keys!

      options[:only]    = Array[options[:only]]   if options[:only] && !options[:only].is_a?(Array)
      options[:except]  = Array[options[:except]] if options[:except] && !options[:except].is_a?(Array)
      options[:limit] ||= {}

      if options[:limit] and !options[:limit].is_a?(Hash)
        options[:limit] = {:string => options[:limit], :text => options[:limit], :decimal => options[:limit], :integer => options[:limit], :float => options[:limit]}
      end
      @validate_lengths_from_database_options = options

      validate :validate_lengths_from_database

      nil
    end

    def validate_lengths_from_database_options
      if defined? @validate_lengths_from_database_options
        @validate_lengths_from_database_options
      else
        # in case we inherited the validations, copy the options so that we can update it in child
        # without affecting the parent
        @validate_lengths_from_database_options = superclass.validate_lengths_from_database_options.inject({}) do |hash, (key, value)|
          value = value.dup if value.respond_to?(:dup)
          hash.update(key => value)
        end
      end
    end
  end

  module InstanceMethods
    def validate_lengths_from_database
      options = self.class.validate_lengths_from_database_options

      if options[:only]
        columns_to_validate = options[:only].map(&:to_s)
      else
        columns_to_validate = self.class.column_names.map(&:to_s)
        columns_to_validate -= options[:except].map(&:to_s) if options[:except]
      end

      columns_to_validate.each do |column|
        column_schema = self.class.columns.find {|c| c.name == column }
        next if column_schema.nil?
        next if column_schema.respond_to?(:array) && column_schema.array
        next unless [:string, :text, :decimal].include?(column_schema.type)
        case column_schema.type
        when :string, :text
          if column_limit = options[:limit][column_schema.type] || column_schema.limit
            validator =
              if ActiveModel::Validations::LengthValidator::RESERVED_OPTIONS.include?(:tokenizer)
                ActiveModel::Validations::LengthValidator.new(
                  :allow_blank => true,
                  :attributes => [column],
                  :maximum => column_limit,
                  :tokenizer => ->(string) { string.bytes }
                )
              else
                UnicodeLengthValidator.new(
                  :allow_blank => true,
                  :attributes => [column],
                  :maximum => column_limit,
                  :too_long => "is too long (maximum is %{count} bytes)"
                )
              end

            validator.validate(self)
          end
        when :decimal
          if column_schema.precision && column_schema.scale
            max_val = (10 ** column_schema.precision)/(10 ** column_schema.scale)
            ActiveModel::Validations::NumericalityValidator.new(:less_than => max_val, :allow_blank => true, :attributes => [column]).validate(self)
          end
        end
      end
    end
  end
end
