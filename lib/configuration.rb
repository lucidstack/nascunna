require "set"

module Nascunna
  class Configuration
    @@cacheables = Set.new()
    @@dependencies = {}
    @@invalidations = {}
    @@expirations = {}

    def initialize(model, method_sym=nil, &block)
      @model = model
      @@cacheables << @model
      if method_sym
        @method_sym = method_sym
        @@dependencies[@model.name] ||= {}
        @@dependencies[@model.name][@method_sym] ||= Set.new
      end
      block.call(self) if block
      return self
    end

    def self.cacheables
      @@cacheables
    end

    def self.dependencies
      @@dependencies
    end

    def self.invalidations
      @@invalidations
    end

    def self.expirations
      @@expirations
    end

    def add_invalidation(base, dependency)
      dest_class = base.reflect_on_association(dependency).class_name.constantize
      @@cacheables << dest_class

      targets = dest_class.reflect_on_all_associations.select do |association|
        association.class_name == base.name
      end

      @@invalidations[dest_class.name] ||= Set.new
      targets.each do |to_invalidate|
        @@invalidations[dest_class.name] << {
          :macro => to_invalidate.macro,
          :association_name => to_invalidate.name,
          :root_name => @model.name,
          :root => to_invalidate.class_name == @model.name,
          :method => @method_sym,
          :activated => false
        }
      end
    end

    def add_dependency(dependency)
      @@dependencies[@model.name][@method_sym] << dependency
    end

    def add_expiration(exp_seconds)
      @@expirations[@model.name] = exp_seconds
    end
  end
end
