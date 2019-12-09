module ActiveRecordLaxIncludes
  def lax_includes
    Thread.current[:active_record_lax_includes_enabled] = true
    yield
  ensure
    Thread.current[:active_record_lax_includes_enabled] = false
  end

  def lax_includes_enabled?
    result = Thread.current[:active_record_lax_includes_enabled]
    if result.nil?
      result = Rails.configuration.respond_to?(:active_record_lax_includes_enabled) &&
                  Rails.configuration.active_record_lax_includes_enabled
    end
    result
  end

  module Base
    def association(name)
      association = association_instance_get(name)

      if association.nil?
        if reflection = self.class._reflect_on_association(name)
          association = reflection.association_class.new(self, reflection)
          association_instance_set(name, association)
        elsif !ActiveRecord.lax_includes_enabled?
          raise ActiveRecord::AssociationNotFoundError.new(self, name)
        end
      end

      association
    end
  end

  module Preloader
    private

    def preloaders_for_reflection(reflection, records, scope)
      records.group_by { |record| record.association(reflection.name).try(:klass) }.map do |rhs_klass, rs|
        preloader_for(reflection, rs).new(rhs_klass, rs, reflection, scope).run
      end
    end

    def grouped_records(association, records, polymorphic_parent)
      h = {}
      records.each do |record|
        reflection = record.class._reflect_on_association(association)
        next if polymorphic_parent && !reflection || !record.association(association).try(:klass)
        (h[reflection] ||= []) << record
      end
      h
    end
  end
end

require 'active_record'

ActiveRecord.send(:extend, ActiveRecordLaxIncludes)
ActiveRecord::Base.send(:prepend, ActiveRecordLaxIncludes::Base)
ActiveRecord::Associations::Preloader.send(:prepend, ActiveRecordLaxIncludes::Preloader)
