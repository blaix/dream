resource(:chore) do
  string :name
  boolean :is_complete
end

# That's it. You have a full API that can persist chores.
# What if you have more complex logic?
# Create a model for the resource as a plain old ruby object...

# ---

# What about models that have extra logic besides persistence? Like sending
# emails, updating third-party services, etc...?

# What about more complex routing? Access control? etc..?

# What about a publish/subscribe pattern?
# Hexagonal architecture (ports and adapters)?
