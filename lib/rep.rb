# **Rep** is a small module to endow any class to make json quickly. It solves four problems:
#
# * Enumerating top level keys for a json structure
# * Providing a convention for the value of those keys
# * Defining attr_accessor's that are prefilled from an options hash given to #initialize
# * Sharing instances to help GC

require 'rep/version'
require 'forwardable'
require 'json'

module Rep
  def self.included(klass)
    klass.extend Forwardable
    klass.extend ClassMethods
    klass.instance_eval {
      class << self
        alias forward delegate

        unless defined?(fields)
          alias fields json_fields
        end

        if defined?(Hashie)
          include HashieSupport
        end
      end

      unless defined?(parse_opts)
        def parse_opts(opts = {})
          # NOOP
        end
      end
    }
  end

  def reset_for_json!
    self.class.all_json_methods.each do |method_name|
      instance_variable_set(:"@#{method_name}", nil)
    end
  end

  def to_hash(name = :default)
    if fields = self.class.json_fields(name)
      fields.reduce({}) do |memo, field|
        field_name, method_name = field.is_a?(Hash) ? field.to_a.first : [field, field]
        begin
          memo[field_name] = send(method_name)
        rescue NoMethodError => e
          message = "There is no method named '#{method_name}' for the class '#{self.class}' for the '#{name}' list of fields : #{e.message}"
          raise NoMethodError.new(message, method_name, e.args)
        end
        memo
      end
    else
      raise "There are no json fields under the name: #{name}"
    end
  end

  def to_json
    JSON.generate(to_hash)
  end

  module ClassMethods
    def register_accessor(acc)
      name, default = acc.is_a?(Hash) ? acc.to_a.first : [acc, nil]
      attr_accessor name
      if default
        define_method name do
          var_name = :"@#{name}"
          instance_variable_get(var_name) || instance_variable_set(var_name, default)
        end
      end
    end

    def initialize_with(*args)
      @initializiation_args = args

      define_singleton_method :initializiation_args do
        @initializiation_args
      end

      args.each { |a| register_accessor(a) }

      define_method(:initialize) { |opts = {}| parse_opts(opts) }

      define_method :parse_opts do |opts|
        @presidential_options = opts
        self.class.initializiation_args.each do |field|
          name = field.is_a?(Hash) ? field.to_a.first.first : field
          instance_variable_set(:"@#{name}", opts[name])
        end
      end
    end

    def json_fields(arg = nil)
      if arg.is_a?(Hash)
        fields, name = arg.to_a.first
        @json_fields ||= {}
        @json_fields[name] = [fields].flatten
      elsif arg.is_a?(Symbol)
        @json_fields ||= {}
        @json_fields[arg]
      elsif arg === nil
        @json_fields || {}
      else
        # TODO: make an exception class
        raise "You can only use a Hash to set fields, a Symbol to retrieve them, or no argument to retrieve all fields for all names"
      end
    end

    def flat_json_fields(side = :right)
      side_number = side == :right ? 1 : 0

      json_fields.reduce([]) do |memo, (name, fields)|
        memo + fields.map do |field|
          if field.is_a?(Hash)
            field.to_a.first[side_number] # [name, method_name]
          else
            field
          end
        end
      end.uniq
    end

    def all_json_fields
      flat_json_fields(:left)
    end

    def all_json_methods
      flat_json_fields(:right)
    end

    # TODO: thread safety
    def shared(opts = {})
      @instance ||= new
      @instance.reset_for_json!
      @instance.parse_opts(opts)
      @instance
    end

    def to_proc
      proc { |obj|
        arr = [obj].flatten
        init_args = @initializiation_args[0..(arr.length-1)]
        opts = Hash[init_args.zip(arr)]
        shared(opts).to_hash
      }
    end
  end

  module HashieSupport
    def to_hash(name = :default)
      Hashie::Mash.new(super)
    end
  end
end
