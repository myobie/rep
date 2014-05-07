# **Rep** is a small module to endow any class to make json quickly. It solves four problems:
#
# 1. Enumerating top level keys for a json structure
# 2. Providing a convention for the value of those keys
# 3. Defining `attr_accessor`'s that are prefilled from an options hash given to `#initialize`
# 4. Sharing instances to help GC
#
# The code is available on [github](http://github.com/myobie/rep).

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
require 'mashed'

require 'rep/version'
module Rep

  # All classes that `include Rep` are extended with `Forwardable`,
  # given some aliases, endowned with `HashieSupport` if Hashie is loaded,
  # and given a delegate method if it doesn't already have one.

  def self.included(klass)
    klass.extend Forwardable
    klass.extend ClassMethods
    klass.instance_eval {
      class << self
        unless defined?(forward)
          alias forward delegate
        end

        unless defined?(fields)
          alias fields json_fields
        end
      end
    }
  end

  # Since a goal is to be able to share instances, we need an easy way to reset a
  # shared instance back to factory defaults. If you memoize any methods that are
  # not declared as json fields, then overried this method and set any memoized
  # variables to nil, then super.

  def reset_for_json!
    self.class.all_json_methods.each do |method_name|
      instance_variable_set(:"@#{method_name}", nil)
    end
  end

  # All the work of generating a hash from an instance is packaged up in one method. Since
  # fields can be aliases in the format `{ :json_key_name => :method_name }`, there
  # is some fancy logic to determine the `field_name` and `method_name` variables.
  #
  #     { :one => :foo }.to_a # => [[:one, :foo]]
  #
  # Right now it will raise if either a field doesn't have a method to provide it's value or
  # if there are no json fields setup for the particular set (which defaults to `:default`).

  def to_hash(name = :default)
    fields = if name.is_a?(Hash)
      hash = name
      if hash.keys.include?(:fields)
        fields = hash[:fields]
      else
        raise "Argument must be either `fields: [...]` or `:symbol`"
      end
    else
      self.class.json_fields(name)
    end

    if fields
      fields.each_with_object({}) do |field, memo|
        field_name, method_name = field.is_a?(Hash) ? field.to_a.first : [field, field]
        if self.respond_to?(method_name)
          memo[field_name] = send(method_name)
        else
          message = "There is no method named '#{method_name}' for the class '#{self.class}' for the '#{name}' list of fields"
          raise NoMethodError.new(message, method_name)
        end
      end
    else
      raise "There are no json fields under the name: #{name}"
    end
  end

  def to_mash(name = :default)
    Mashed::Mash.new(to_hash(name))
  end

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
    # If your class already has an `#iniatialize` method then this will overwrite it (so don't use it). `#initialize_with`
    # does not have to be used to use any other parts of Rep.

    def initialize_with(*args, &blk)
      @initializiation_args = args

      # Remember what args we normally initialize with so we can refer to them when building shared instances.

      if defined?(define_singleton_method)
        define_singleton_method :initializiation_args do
          @initializiation_args
        end
      else
        singleton = class << self; self end
        singleton.send :define_method, :initializiation_args, lambda { @initializiation_args }
      end

      # Create an `attr_accessor` for each one. Defaults can be provided using the Hash version { :arg => :default_value }

      args.each { |a| register_accessor(a) }

      define_method(:initialize) { |opts={}|
        parse_opts(opts)
      }

      # `#parse_opts` is responsable for getting the `attr_accessor` values prefilled. Since defaults can be specified, it
      # must negotiate Hashes and use the first key of the hash for the `attr_accessor`'s name.

      define_method :parse_opts do |opts|
        @rep_options = opts
        blk.call(opts) unless blk.nil?
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

    # `#flat_json_fields` is just a utility method to DRY up the next two methods, because their code is almost exactly the same,
    # it is not intended for use directly and might be confusing.

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

    # We need a way to get a flat, uniq'ed list of all the fields accross all field sets. This is that.

    def all_json_fields
      flat_json_fields(:left)
    end

    # We need a wya to get a flat, uniq'ed list of all the method names accross all field sets. This is that.

    def all_json_methods
      flat_json_fields(:right)
    end

    # An easy way to save on GC is to use the same instance to turn an array of objects into hashes instead
    # of instantiating a new object for every object in the array. Here is an example of it's usage:
    #
    #     class BookRep
    #       initialize_with :book_model
    #       fields :title => :default
    #       forward :title => :book_model
    #     end
    #
    #     BookRep.shared(:book_model => Book.first).to_hash # => { :title => "Moby Dick" }
    #     BookRep.shared(:book_model => Book.last).to_hash  # => { :title => "Lost Horizon" }
    #
    # This should terrify you. If it doesn't, then this example will:
    #
    #     book1 = BookRep.shared(:book_model => Book.first)
    #     book2 = BookRep.shared(:book_model => Book.last)
    #
    #     boo1.object_id === book2.object_id # => true
    #
    # **It really is a shared object.**
    #
    # You really shouldn't use this method directly for anything.

    def shared(opts = {})
      @pointer = (Thread.current[:rep_shared_instances] ||= {})
      @pointer[object_id] ||= new
      @pointer[object_id].reset_for_json!
      @pointer[object_id].parse_opts(opts)
      @pointer[object_id]
    end

    # The fanciest thing in this entire library is this `#to_proc` method. Here is an example of it's usage:
    #
    #     class BookRep
    #       initialize_with :book_model
    #       fields :title => :default
    #       forward :title => :book_model
    #     end
    #
    #     Book.all.map(&BookRep) # => [{ :title => "Moby Dick" }, { :title => "Lost Horizon " }]
    #
    # And now I will explain how it works. Any object can have a to_proc method and when you call `#map` on an
    # array and hand it a proc it will in turn hand each object as an argument to that proc. What I've decided
    # to do with this object is use it the options for a shared instance to make a hash.
    #
    # Since I know the different initialization argumants from a call to `initialize_with`, I can infer by order
    # which object is which option. Then I can create a Hash to give to `parse_opts` through the `shared` method.
    # I hope that makes sense.
    #
    # It allows for extremely clean Rails controllers like this:
    #
    #     class PhotosController < ApplicationController
    #       respond_to :json, :html
    #
    #       def index
    #         @photos = Photo.paginate(page: params[:page], per_page: 20)
    #         respond_with @photos.map(&PhotoRep)
    #       end
    #
    #       def show
    #         @photo = Photo.find(params[:id])
    #         respond_with PhotoRep.new(photo: @photo)
    #       end
    #     end

    def to_proc
      proc { |obj|
        arr = [obj].flatten
        init_args = @initializiation_args[0..(arr.length-1)]
        opts = Hash[init_args.zip(arr)]
        shared(opts).to_hash
      }
    end
  end
end
