# Dream Framework

## A framework idea for distributed applications.

Define your resources in ruby. Interact with them from anywhere in any language
that has an adapter.

**Goals (aka Wishlist):**

* Simply define resources that are automatically mapped to api endpoints
* Resources reveal their schema via the api, allowing client applications,
  using adapters, to create models without redefining the schema.
* Resource persistence is decoupled, allowing swappable stores (memory,
  database, etc) based on environment.
* Unit and integration testing made easy for both host and client applications.
* Socket connections with changes pushed to clients

**Main components:**

* Mapper: map objects as resources by describing their attributes, or (in
  adapters) by reading the exposed schema of a remote resource.
* Store: persist resources (usually to a database).
* Router: map a REST-like api to the methods on the resource store.

## Plain old ruby objects...

Dream works with plain old ruby objects. For example:

```ruby
class Chore
  attr_accessor :name, :last_completed

  def complete?
    last_completed == Date.today
  end

  def complete=(val)
    self.last_completed = val ? Date.today : nil
  end
end
```

## ...as resources

All you need to expose a complete REST-like API for this object, is to create
a Dream application and map `Chore` as a resource:

```ruby
MyApp = Dream::App.new

MyApp.resources[Chore] do
  attributes do
    string "name"
    boolean "complete?", as: "is_complete", persist: false
    date "last_completed", readonly: true
  end
end
```

Now chores can be fetched from and saved to a resource store (usually a
database - more on that later) through an intuitive API, with `last_completed`
not writeable via the API, and `complete` exposed via the API but not saved to
the resource store:

```ruby
MyApp.start
```

```
# Create a couple chores:

POST /chores {name: "Laundry"} # => 201 Created
{id: 1, name: "Laundry", last_completed: null, is_complete: false}

POST /chores {name: "Trash"} # => 201 Created
{id: 2, name: "Trash", last_completed: null, is_complete: false}

# Complete a chore (pretend today is Jan. 1, 2013):

PATCH /chores/1 {is_complete: true} # => 200 OK
{id: 1, name: "Laundry", last_completed: "2013-01-13", is_complete: true}

# Get all chores:

GET /chores # => 200 OK
[{id: 1, name: "Laundry", last_completed: "2013-01-13, is_complete: true},
 {id: 2, name: "Trash", last_completed: null, is_complete: false}]

# Filter chores by name:

GET /chores?name=Trash # => 200 OK
[{id: 2, name: "Trash", last_completed: null, is_complete: false}]

# Get a single chore:

GET /chores/1 # => 200 OK
{id: 1, name: "Laundry", last_completed: "2013-01-13", is_complete: true}

GET /chores/99 # => 404 Not Found

# Delete a chore:

DELETE /chores/1 # => 204 No Content
```

Resources also reveal their schema via the API. This lets client
applications declare simple models that bind to remote resources without
duplicating the schema.

```
GET /chores/schema
{
    name: {
        type: "string"
    },
    last_completed: {
        type: "date",
        readonly: true
    },
    is_complete: {
        type: "boolean"
    }
}
```

Any client application with an adapter available in their language can then
interact with the api simply:

```
bower install dream
```

```javascript
// => GETs /chores/schema to build full model
Chore = Dream.RemoteResource("Chore")

chore = new Chore({name: "Dishes"});
chore.save(); // => POSTs to /chores with {name: "Dishes"}

chore.complete = true;
chore.save() // => PATCH to /chores/[chore.id] with {complete: true}
```

Javascript is the most obvious exmample, but there can be client adapters in
any language that can read and parse remote JSON. For example, the same host
that powers this javascript app could also power an iPhone app using a ruby
adapter with RubyMotion, keeping all data in sync.

## Resource Stores

Under the hood, resources are persisted using an instance of `Dream::Store`.
It has all the usual CRUD operations:

```ruby
# a store is defined for you automatically
store = MyApp.stores[Chore] # => #<Dream::Store>

# uuids are created automatically
chore = store.create(name: "name")
chore_id = chore.id

# get one chore by uuid
chore = store.get(chore_id) # => #<Chore:chore_id>

# or get all, optionally filtering by attributes
store.all # => [#<Chore:chore_id>, ...]
store.all(last_completed: some_date) # => [#<Chore:chore_id>, ...]

# save changes on an object by passing it back into the store
chore.name = "new name"
store.save(chore)

# or update or delete objects directly in the store by uuid
store.update(chore_id, name: "new name") # => update directly in store
store.delete(chore_id)
```

If you need to do a lot of interaction with the store, you can temporarily
extend your plain old ruby object with persitence knowledge:

```ruby
chore = Chore.new
chore.name = "trash"

chore.extend(Dream::Store)
chore.save

chore.update(name: "new name")
chore.delete

Chore.extend(Dream::Store)
Chore.all # => [#<Chore:...>, ...]
```

You can add your own methods to the store like this:

```ruby
MyApp.stores[Chore] do
  def complete
    all(last_completed: Date.today)
  end
end
```

You can then expose your new method via the API using the router...

## Resource Routes

The API works by mapping paths and request data to methods and arguments sent
to the resource store. For example:

* `GET /chores/123` maps to `MyApp.stores[Chore].get(123)`
* `GET /chores?name=Trash` maps to `MyApp.stores[Chore].all(name: "Trash")`
* `POST /chores {name: "Laundry"}` maps to 
  `MyApp.stores[Chore].create(name: "Laundry")`
* etc...

All of the HTTP verbs are mapped to methods on the store. If you were to
define them explicitely, it would look like this:

```ruby
MyApp.routes[Chore] do
  path /^$/ do
    get "all"
    post "create", success: 201
  end

  path /^(?<id>\x+)$/ do
    get "get"
    put "replace"
    patch "update"
    delete "delete", success: 204
  end
end
```    

Named capture groups, query parameters, and request data are passed as keyword
arguments to the specified method.

Unless otherwise specified, 200 is used for all successful requests. A
successful request is any that did not raise an exception. If an exception is
raised, the exception's `#status_code` method is returned, with 500 being
the default. Many common exceptions are defined by the framework, for example:

* `Dream::Errors::NotFound#status_code`: 404
* `Dream::Errors::NotImplemented#status_code`: 501
* `Dream::Errors::Unauthorized#status_code`: 401

Knowing this, you can exclude any of the default store mappings by raising an
error:

```ruby
MyApp.stores[Chore] do
  def replace
    raise Dream::Errors::NotImplemented.new("We don't allow replacing chores")
  end
end
```
