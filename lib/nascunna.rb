require "configuration"
require "cacheable"

module Nascunna

  def self.redis
    @redis
  end

  def self.redis=(redis_instance)
    @redis = redis_instance
  end

  def self.add_model(model)
    @model = model
    yield(self)
    Nascunna::Configuration.cacheables.each do |model|
      model.class_eval <<-EOS
        include Nascunna::Cacheable
      EOS
    end
  end

  def self.add_dependency(method_sym, dependencies, base=@model)
    Nascunna::Configuration.new(@model, method_sym) do |graph|
      graph.add_dependency(dependencies)
      recursively_compute_deps(graph, method_sym, dependencies, base)
    end
  end

  def self.connect(method_sym, sources)
    connected_dependencies = Array(sources).collect do |source|
      Nascunna::Configuration.dependencies[@model.name][source].to_a
    end.flatten(1).uniq

    connected_dependencies = connected_dependencies[0] if connected_dependencies.size == 1
    self.add_dependency(method_sym, connected_dependencies)
  end

  private

  def self.recursively_compute_deps(graph, method_sym, dependencies, base)
    case dependencies
    when Symbol, String
      graph.add_invalidation(base, dependencies.to_sym)
    when Hash
      dependencies.each do |key, value|
        graph.add_invalidation(base, key.to_sym)
        new_base = base.reflect_on_association(key)
        raise "Polymorphic associations (#{key}) not supported yet!" if new_base.options[:polymorphic]
        new_base = new_base.class_name.constantize
        self.recursively_compute_deps(graph, method_sym, value, new_base)
      end
    when Array
      dependencies.each do |dependency|
        self.recursively_compute_deps(graph, method_sym, dependency, base)
      end
    else
      raise ArgumentError, "dependencies type not supported"
    end
  end

end
