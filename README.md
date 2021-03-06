# Rep

```
                               /T /I
                              / |/ | .-~/
                          T\ Y  I  |/  /  _
         /T               | \I  |  I  Y.-~/
        I l   /I       T\ |  |  l  |  T  /
 __  | \l   \l  \I l __l  l   \   `  _. |
 \ ~-l  `\   `\  \  \\ ~\  \   `. .-~   |
  \   ~-. "-.  `  \  ^._ ^. "-.  /  \   |
.--~-._  ~-  `  _  ~-_.-"-." ._ /._ ." ./
 >--.  ~-.   ._  ~>-"    "\\   7   7   ]
^.___~"--._    ~-{  .-~ .  `\ Y . /    |
 <__ ~"-.  ~       /_/   \   \I  Y   : |
   ^-.__           ~(_/   \   >._:   | l______
       ^--.,___.-~"  /_/   !  `-.~"--l_ /     ~"-.
              (_/ .  ~(   /'     "~"--,Y   -=b-. _)
               (_/ .  \  :           / l      c"~o \
                \ /    `.    .     .^   \_.-~"~--.  )
                 (_/ .   `  /     /       !       )/
                  / / _.   '.   .':      /        '
                  ~(_/ .   /    _  `  .-<_
                    /_/ . ' .-~" `.  / \  \          ,z=.
                    ~( /   '  :   | K   "-.~-.______//
                      "-,.    l   I/ \_    __{--->._(==.
                       //(     \  <    ~"~"     //
                      /' /\     \  \     ,v=.  ((
                    .^. / /\     "  }__ //===-  `
                   / / ' '  "-.,__ {---(==-
                 .^ '       :  T  ~"   ll
                / .  .  . : | :!        \\
               (_/  /   | | j-"          ~^
                 ~-<_(_.^-~"
```

A library for writing authoritative representations of objects for pages and apis.

## Installation

Add this line to your application's Gemfile:

    gem 'rep'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rep

## Usage

`include Rep` into any class. See [nathanherald.com/rep](http://nathanherald.com/rep) for complete docs on every method.

## Examples

```ruby
# imagine Photo is an ActiveRecord model with fields for title, exif, location, and user_id

class PhotoRep
  include Rep

  initialize_with :photo

  fields [:url, :title, :exif, :location, :user] => :default

  forward [:title, :exif, :location] => :photo
  forward :user => :user_rep

  def url
    full_photo_url(photo.name)
  end

  def user
    UserRep.shared(user: photo.user)
  end
end

# imagine User is an ActiveRecord model with fields for name, email, and location

class UserRep
  include Rep

  initialize_with :user

  fields [:name, :email, :location] => :default
  fields [:id, :admin].concat(fields(:default)) => :admin

  forward fields(:admin) => :user
end

# You can now do crazy stuff like
UserRep.new(user: User.first).to_hash.keys # => [:name, :email, :location]

# To save from creating lots of objects, you can use a shared class that is reset fresh
UserRep.shared(user: User.first).to_hash # => { name: "Nathan Herald:, ...

# You can use class to proc (that makes a hash using the shared instance)
User.all.map(&UserRep) # => [{ name: "Nathan Herald" ...

# or maybe find all photos which will embed all users (and only ever make one instance each of PhotoRep and UserRep)
Photo.all.map(&PhotoRep).to_json
```

### Any class

You don't have to have a Rep per model and Rep's can represent multiple objects at once. It's POROs.

```ruby
class ProjectReport
  include Rep
  initialize_with :project, :active_users, :orders
  fields [:name, :date, :count, :total_gross_cost, :cost_per_active_user] => :default
  forward :date => :project
  forward :count => :orders

  def name
    "#{project.name} Report"
  end

  def total_gross_cost
    orders.reduce(0.0) { |memo, order| memo += order.total_gross_cost.to_f }
  end

  def cost_per_active_user
    active_users.count.to_f / total_gross_cost.to_f
  end
end
```

### Rails

A possible controller
```ruby
class PhotosController < ApplicationController
  respond_to :json, :html

  def index
    @photos = Photo.paginate(page: params[:page], per_page: 20)
    respond_with @photos.map(&PhotoRep)
  end

  def show
    @photo = Photo.find(params[:id])
    respond_with PhotoRep.new(photo: @photo)
  end
end
```
