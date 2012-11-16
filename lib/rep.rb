# **Rep** is a small module to endow any class to make json quickly. It solves four problems:
#
# 1. Enumerating top level keys for a json structure
# 2. Providing a convention for the value of those keys
# 3. Defining `attr_accessor`'s that are prefilled from an options hash given to `#initialize`
# 4. Sharing instances to help GC

require 'rep/version'

# `Forwardable` is in the stdlib and allows ruby objects to delegate methods off to other objects. An example:
#
#     class A
#       extend Forwardable
#       delegate [:length, :first] => :@array
#       def initialize(array = [])
#         @array = array
#       end
#     end
#
#     A.new([1,2,3]).length # => 3
#     A.new([1,2,3]).first  # => 1

require 'forwardable'

# `JSON::generate` and `JSON::decode` are much safer to use than `Object#to_json`.

require 'json'

module Rep

  # All classes that `include Rep` are extended with `Forwardable`,
  # given an alias `forward` for `delegate` (because it sounds better),
  # an alias `fields` for `json_fields` unless it's already defined (because it sounds better),
  # include `HashieSupport` which wraps all return values from `#to_hash` with `Hashie::Mash`,
  # and setup an empty `parse_opts` if there is not already one which is used for shared instances so that options can be parsed without going through `#initialize`.

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
        def parse_opts(opts = {}); end
      end
    }
  end

  # Since a goal is to be able to share instances, we need an easy way to reset a
  # shared instance back to factory defaults. If you memoize any methods that are
  # not declared as json fields, then overried this method and super.

  def reset_for_json!
    self.class.all_json_methods.each do |method_name|
      instance_variable_set(:"@#{method_name}", nil)
    end
  end

  # All the work of generating a hash from an instance is packaged up in one method. Since
  # fields can be aliases themselves in the format { :json_key_name => :method_name }, there
  # is some fancy logic to determine the `field_name` and `method_name` variables.
  #
  # { :one => :foo }.to_a => [[:one, :foo]]

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

  # `#to_json` is only for compatability. Use `JSON::generate` instead of delegating to the hash object's `#to_json` because I don't trust it.

  def to_json
    JSON.generate(to_hash)
  end

  module ClassMethods

    # Defines an attr_accessor with a default value. The default for default is nil. Example:
    #
    #     class A
    #       register_accessor :name => "No Name"
    #     end
    #
    #     A.new.name # => "No Name"

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

    # Defines an `#initialize` method that accepts a Hash argument and copies some keys out into `attr_accessors`.
    # If your class already has an `#iniatialize` method then this will overwrite it. `#initialize_with` does not have to be used
    # to use any other parts of Rep.

    def initialize_with(*args)
      @initializiation_args = args

      # Remember what args we normally initialize with so we can refer to them when building shared instances.

      define_singleton_method :initializiation_args do
        @initializiation_args
      end

      # Create an `attr_accessor` for each one. Defaults can be provided using the Hash version { :arg => :default_value }

      args.each { |a| register_accessor(a) }

      # `#initialize` only parses the options

      define_method(:initialize) { |opts = {}| parse_opts(opts) }

      # `#parse_opts` is responsable for getting the `attr_accessor` values prefilled. Since defaults can be specified, it
      # must negotiate Hashes and use the first key of the hash for the `attr_accessor`'s name.

      define_method :parse_opts do |opts|
        @presidential_options = opts
        self.class.initializiation_args.each do |field|
          name = field.is_a?(Hash) ? field.to_a.first.first : field
          instance_variable_set(:"@#{name}", opts[name])
        end
      end
    end

    # `#json_fields` setups up some class instance variables to remember sets of top level keys for json structures. Example:
    #
    #     class A
    #       json_fields [:one, :two, :three] => :default
    #     end
    #
    #     A.json_fields(:default) # => [:one, :two, :three]
    #
    # There is a general assumption that each top level key's value is provided by a method of the same name on an instance
    # of the class. If this is not true, a Hash syntax can be used to alias to a different method name. Example:
    #
    #     class A
    #       json_fields [{ :one => :the_real_one_method }, :two, { :three => :some_other_three }] => :default
    #     end
    #
    # Once can also set multiple sets of fields. Example:
    #
    #     class A
    #       json_fields [:one, :two, :three] => :default
    #       json_fields [:five, :two, :six] => :other
    #     end
    #
    # And all fields are returned by calling `#json_fields` with no args. Example:
    #
    #     A.json_fields # => { :default => [:one, :two, :three], :other => [:five, :two, :six] }

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
