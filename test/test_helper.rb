require 'minitest/autorun'
require 'minitest/pride'
require 'rep'

class User < Struct.new(:name, :email, :location)
end

class Photo < Struct.new(:name, :location, :exif)
end
