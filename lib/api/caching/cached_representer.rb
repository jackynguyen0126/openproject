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
          json_rep = OpenProject::Cache.fetch(represented) do
            super
          end

          hash_rep = ::JSON::parse(json_rep)

          apply_link_cache_ifs(hash_rep)

          ::JSON::dump(hash_rep)
        end

        private

        def apply_link_cache_ifs(hash_rep)
          link_conditions = representable_attrs['links']
                            .link_configs
                            .select { |config, _block| config[:cache_if] }

          link_conditions.each do |config, _block|
            condition = config[:cache_if]
            name = config[:rel]

            displayed = instance_exec(&condition)

            hash_rep['_links'].delete(name.to_s) unless displayed
          end
        end
      end

      class_methods do
        def link(name, options = {}, &block)
          rel_hash = name.is_a?(Hash) ? name : { rel: name }
          super(rel_hash.merge(options), &block)
        end
      end
    end
  end
end
