require 'shrine'
require 'roda'
require 'json'

class Shrine
  module Plugins
    module Webhook

      def self.load_dependencies(uploader, *)
        uploader.plugin :rack_file
      end

      def self.configure uploader, opts = {}
        uploader.assign_webhook_endpoint(App) unless uploader.const_defined?(:WebhookEndpoint)
      end

      module ClassMethods
        # Assigns the subclass a copy of the upload endpoint class.
        def inherited(subclass)
          super
          subclass.assign_webhook_endpoint self::WebhookEndpoint
        end

        # Assigns the sub-classed endpoint as the `UploadEndpoint` constant.
        def assign_webhook_endpoint klass
          endpoint_class = Class.new klass
          endpoint_class.opts[:shrine_class] = self
          const_set :WebhookEndpoint, endpoint_class
        end
      end

      module AttacherMethods
        def endpoint_url
          # TODO: This should be a configuration on the plugin
          Rails.application.routes.url_helpers.send _url_helper, _url_options
        end

        def default_url_options
        end

        private

        def _url_helper
          "#{shrine_class.name.underscore}_webhook_endpoint_url"
        end

        def _url_options
          default_url_options || Rails.application.routes.default_url_options
        end
      end

      class App < Roda
        route do |r|
          r.on ':t/:id/:name' do |type, id, name|
            r.post 'callback' do
              record = type.classify.constantize.find id
              attacher = record.send "#{name}_attacher"
              promote attacher, JSON.parse(r.body.read)
              response.status = 200
              request.halt
            end
          end
        end

        private

        def promote attacher, payload
          attacher.promote attacher.get, phase: :store, payload: payload
        end
      end
    end

    register_plugin :webhook, Webhook
  end
end
