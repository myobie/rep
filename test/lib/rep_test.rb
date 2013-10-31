require 'test_helper'

describe Rep do

  def new_rep_class(&blk)
    klass = Class.new
    klass.send :include, Rep
    if block_given?
      klass.class_eval &blk
    end
    klass
  end

  it "includes forwardable" do
    new_rep_class.must_respond_to :delegate
  end

  it "aliases delegate to foward" do
    new_rep_class.must_respond_to :forward
  end

  it "aliases fields to json_fields" do
    new_rep_class.must_respond_to :fields
  end

  it "can have fields" do
    klass = new_rep_class do
      fields [:foo, :bar] => :default
    end
    klass.fields(:default).must_equal [:foo, :bar]
  end

  it "can create initialize method" do
    klass = new_rep_class do
      initialize_with :foo, :bar
    end
    inst = klass.new(:foo => 'foo123')
    inst.foo.must_equal 'foo123'
    inst.bar.must_be_nil
  end

  it "can have default initialization options" do
    klass = new_rep_class do
      initialize_with :foo, { :bar => "barbar" }
    end
    inst = klass.new(:foo => 'foofoo')
    inst.bar.must_equal 'barbar'
  end

  it "can overried default initialization options" do
    klass = new_rep_class do
      initialize_with :foo, { :bar => "barbar" }
    end
    inst = klass.new(:bar => 'notbar')
    inst.bar.must_equal 'notbar'
    inst.foo.must_be_nil
  end

  it "can take a block for initialization custimization" do
    klass = new_rep_class do
      initialize_with :foo do |opts|
        opts[:foo] &&= opts[:foo].to_s
      end
    end
    inst = klass.new(:foo => :bar)
    inst.foo.must_equal 'bar'
  end

  it "should accept multiple sets of fields" do
    klass = new_rep_class do
      fields [:one, :four] => :default
      fields [:one, :two, :three] => :superset
    end
    klass.fields(:default).length.must_equal 2
    klass.fields(:superset).length.must_equal 3
  end

  it "should know all uniq fields" do
    klass = new_rep_class do
      fields [:one, :four] => :default
      fields [:one, :two, :three] => :superset
    end
    fields = klass.all_json_fields.map { |f| f.to_s }.sort
    fields.must_equal [:one, :four, :two, :three].map { |f| f.to_s }.sort
  end

  it "should send fields to instance to make hash" do
    klass = new_rep_class do
      fields [:one, :two, :three] => :default
      def one; 1; end
      def two; 2; end
      def three; 3; end
    end
    klass.new.to_hash.must_equal :one => 1, :two => 2, :three => 3
  end

  it "should send fields to instance to make json" do
    klass = new_rep_class do
      fields [:one, :two, :three] => :default
      def one; 1; end
      def two; 2; end
      def three; 3; end
    end
    klass.new.to_json.must_equal '{"one":1,"two":2,"three":3}'
  end

  it "should let fields alias to method names" do
    klass = new_rep_class do
      fields [{ :one => :real_one }, :two, :three] => :default
      def real_one; 1; end
      def two; 2; end
      def three; 3; end
    end
    klass.new.to_json.must_equal '{"one":1,"two":2,"three":3}'
  end

  it "should know all the methods for the fields" do
    klass = new_rep_class do
      fields [{ :one => :real_one }, :two, :three] => :default
      def real_one; 1; end
      def two; 2; end
      def three; 3; end
    end
    klass.all_json_methods.must_equal [:real_one, :two, :three]
  end

  it "should know all the field names for the fields" do
    klass = new_rep_class do
      fields [{ :one => :real_one }, :two, :three] => :default
      def real_one; 1; end
      def two; 2; end
      def three; 3; end
    end
    klass.all_json_fields.must_equal [:one, :two, :three]
  end

  it "should do symbol to instance craziness" do
    klass = new_rep_class do
      initialize_with :hash
      fields :keys => :default
      def keys
        hash.keys.map { |k| k.to_s }.sort
      end
    end
    hashes = [{ :one => 1, :two => 2 },
              { :three => 3, :four => 4 },
              { :one => 1, :five => 5 }]
    result = [{ "keys" => ["one", "two"] }, { "keys" => ["four", "three"] }, { "keys" => ["five", "one"] }]
    JSON.parse(hashes.map(&klass).to_json).must_equal result
  end

  describe "forward" do
    class Forwardtest
      include Rep
      attr_reader :target
      def initialize
        @target = "Hello, I am a string"
      end
      forward [:length] => :target
    end

    it "should forward (delegate)" do
      assert_equal 20, Forwardtest.new.length
    end
  end

  describe "shared" do

    User = Struct.new(:name, :age)
    def users
      @users ||= %w(Nathan 28 Jason 31 Justin 23).each_slice(2).
                   map { |name, age| User.new(name, age.to_i) }
    end
    class UserRep
      include Rep
      initialize_with :user
      fields [:name, :age, :random_number] => :default
      forward fields(:default) => :user

      def random_number
        @random_number ||= rand(100)
      end
    end

    it "should memoize random_number" do
      rep = UserRep.new(:user => users.first)
      rep.random_number.must_equal rep.random_number
    end

    it "should get a clean instance each time" do
      num1 = UserRep.shared(:user => users.first).random_number
      num2 = UserRep.shared(:user => users.first).random_number
      num1.wont_equal num2
    end

    it "should be really really shared" do
      rep1 = UserRep.shared(:user => users.first)
      rep2 = UserRep.shared(:user => users.last)
      rep1.must_equal rep2
      rep1.name.must_equal rep2.name
    end

  end

end
