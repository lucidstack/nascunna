module Nascunna
  module Cacheable
    def self.included(model)
      model.send :extend, ClassMethods
      model.send :activate_invalidations
    end

    module ClassMethods
      def expires_in(exp_seconds)
        Nascunna::Configuration.new(self).add_expiration(exp_seconds)
      end

      def cache(method_sym, opts={})
        original_method = :"_uncached_#{method_sym}"
        exp_seconds = opts[:expires_in] || Nascunna::Configuration.expirations[self.name]
        class_eval <<-EOS

          alias #{original_method} #{method_sym}

          if instance_method(:#{method_sym}).arity == 0
            def #{method_sym}
              if value = $redis.get("cache:#{self}:\#\{self.id\}:#{method_sym}")
                return Marshal.load(value)
              end

              value = #{original_method}
              if #{exp_seconds.present?}
                $redis.setex("cache:#{self}:\#\{self.id\}:#{method_sym}", #{exp_seconds.to_i}, Marshal.dump(value))
              else
                $redis.set("cache:#{self}:\#\{self.id\}:#{method_sym}", Marshal.dump(value))
              end
              return value
            end

          else

            def #{method_sym}(*args)
              key = Marshal.dump(args)
              if value = $redis.hget("cache:#{self}:\#\{self.id\}:#{method_sym}", key)
                return Marshal.load(value)
              end

              value = #{original_method}(*args)
              $redis.hset("cache:#{self}:\#\{self.id\}:#{method_sym}", key, Marshal.dump(value))
              $redis.expire("cache:#{self}:\#\{self.id\}:#{method_sym}", #{exp_seconds.to_i}) if #{exp_seconds.present?}
              return value
            end

          end
        EOS
        self.add_direct_invalidation(self, {
          :method => method_sym,
          :association_name => :self,
          :root_name => self.name,
          :macro => :belongs_to,
          :activated => false
        }) if opts[:self_invalidates]
      end

      protected

      def add_direct_invalidation(model, opts)
        model.class_eval <<-EOS
          after_commit :invalidate_#{opts[:root_name]}_#{opts[:method]}

          if #{opts[:macro].inspect} == :belongs_to
            def invalidate_#{opts[:root_name]}_#{opts[:method]}(from=nil)
              return "cache:#{opts[:root_name]}:\#\{self.instance_eval("#{opts[:association_name]}").id\}:#{opts[:method]}"
            end

          else
            def invalidate_#{opts[:root_name]}_#{opts[:method]}(from=nil)
              association_ids = self.instance_eval("#{opts[:association_name]}").collect(&:id)
              return association_ids.collect{|id| "cache:#{opts[:root_name]}:\#\{id\}:#{opts[:method]}"} if association_ids.any?
              return []
            end

          end

          private :invalidate_#{opts[:root_name]}_#{opts[:method]}
        EOS
        opts[:activated] = true
        opts
      end

      def add_indirect_invalidation(model, opts)
        model.class_eval <<-EOS

          after_commit :invalidate_#{opts[:root_name]}_#{opts[:method]}

          if #{opts[:macro].inspect} == :belongs_to
            def invalidate_#{opts[:root_name]}_#{opts[:method]}(from=nil)
              if from.nil?
                $redis.pipelined do
                  $redis.del(self.instance_eval("#{opts[:association_name]}").send(:invalidate_#{opts[:root_name]}_#{opts[:method]}, self).flatten)
                end
              else
                return self.instance_eval("#{opts[:association_name]}").send(:invalidate_#{opts[:root_name]}_#{opts[:method]}, self)
              end
            end
          else
            def invalidate_#{opts[:root_name]}_#{opts[:method]}(from=nil)
              if from.nil?
                $redis.pipelined do
                  $redis.del(self.instance_eval("#{opts[:association_name]}").collect do |association|
                    association.send(:invalidate_#{opts[:root_name]}_#{opts[:method]}, self)
                  end.flatten)
                end
              else
                return self.instance_eval("#{opts[:association_name]}").collect do |association|
                  association.send(:invalidate_#{opts[:root_name]}_#{opts[:method]}, self)
                end
              end
            end
          end

          private :invalidate_#{opts[:root_name]}_#{opts[:method]}
        EOS
        opts[:activated] = true
        opts
      end

      private

      def activate_invalidations
        return unless invalidations = Nascunna::Configuration.invalidations[self.name]
        Nascunna::Configuration.invalidations[self.name] = invalidations.collect do |invalidation|
          unless invalidation[:activated]
            if invalidation[:root]
              add_direct_invalidation(self, invalidation)
            else
              add_indirect_invalidation(self, invalidation)
            end
          end
          invalidation
        end
      end

    end
  end
end
