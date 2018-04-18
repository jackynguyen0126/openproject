#-- encoding: UTF-8

#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2018 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See docs/COPYRIGHT.rdoc for more details.
#++

module API
  module Caching
    module CachedRepresenter
      extend ::ActiveSupport::Concern

      included do
        def to_json(*args)
          return super if no_caching?

          cached_json_rep = OpenProject::Cache.fetch(json_cache_key) do
            with_caching_state :cacheable do
              super
            end
          end

          uncached_json_rep = with_caching_state :uncacheable do
            super
          end

          cached_hash_rep = ::JSON::parse(cached_json_rep)

          apply_link_cache_ifs(cached_hash_rep)
          apply_property_cache_ifs(cached_hash_rep)

          add_uncacheable_links(cached_hash_rep)

          uncached_hash_rep = ::JSON::parse(uncached_json_rep)
          hash_rep = uncached_hash_rep.deep_merge(cached_hash_rep)

          ::JSON::dump(hash_rep)
        end

        protected

        attr_accessor :caching_state

        private

        def apply_link_cache_ifs(hash_rep)
          link_conditions = representable_attrs['links']
                            .link_configs
                            .select { |config, _block| config[:cache_if] }

          link_conditions.each do |(config, _block)|
            condition = config[:cache_if]
            next if instance_exec(&condition)

            name = config[:rel]

            delete_from_hash(hash_rep, '_links', name)
          end
        end

        def apply_property_cache_ifs(hash_rep)
          attrs = representable_attrs
                  .select { |_name, config| config[:cache_if] }

          attrs.each do |name, config|
            condition = config[:cache_if]
            next if instance_exec(&condition)

            hash_name = (config[:as] && instance_exec(&config[:as])) || name

            delete_from_hash(hash_rep, config[:embedded] ? '_embedded' : nil, hash_name)
          end
        end

        def add_uncacheable_links(hash_rep)
          link_conditions = representable_attrs['links']
                            .link_configs
                            .select { |config, _block| config[:uncacheable] }

          link_conditions.each do |config, block|
            name = config[:rel]
            block_result = instance_exec(&block)

            if block_result
              hash_rep['_links'][name] = block_result
            else
              hash_rep['_links'].delete(name)
            end
          end
        end

        # Overriding Roar::Hypermedia#perpare_link_for
        # to remove the cache_if option which would otherwise
        # be visible in the output
        def prepare_link_for(href, options)
          super(href, options.except(:cache_if))
        end

        # Overriding Roar::Hypbermedia#combile_links_for
        # to remove all uncacheable links if the caching_state is set to :cacheable
        def compile_links_for(configs, *args)
          current_configs = case caching_state
                            when :cacheable
                              configs.reject { |c| c.first[:uncacheable] }
                            when :uncacheable
                              configs.select { |c| c.first[:uncacheable] }
                            else
                              configs
                            end

          super(current_configs, *args)
        end

        def json_cache_key
          parts = self.class.name.to_s.split('::') + ['json', I18n.locale, represented]

          OpenProject::Cache::CacheKey.key(*parts)
        end

        def delete_from_hash(hash, path, key)
          pathed_hash = path ? hash[path] : hash

          pathed_hash.delete(key.to_s) if pathed_hash
        end

        def representable_map(*)
          ret = super

          current_map = case caching_state
                        when :cacheable
                          ret.reject { |b| b[:uncacheable] }
                        when :uncacheable
                          ret.select { |b| b[:uncacheable] }
                        else
                          ret
                        end

          Representable::Binding::Map.new(current_map)
        end

        def with_caching_state(state)
          self.caching_state = state
          ret = yield
          self.caching_state = nil
          ret
        end

        def no_caching?
          false
        end
      end

      class_methods do
        def link(name, options = {}, &block)
          rel_hash = name.is_a?(Hash) ? name : { rel: name }
          super(rel_hash.merge(options), &block)
        end

        def links(name, options = {}, &block)
          rel_hash = name.is_a?(Hash) ? name : { rel: name }
          super(rel_hash.merge(options), &block)
        end
      end
    end
  end
end
