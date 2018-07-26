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

        def webhook_callback identifier, request
          raise "need to implement #{self.name}#webhook_callback(identifier, request)"
        end

        def webhook_callback_failed! exception, identifier, request
          Rollbar.warning exception if defined? Rollbar
          # puts "ERROR: #{exception.class.name.inspect}"
          # puts identifier
          # puts request
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

        def webhook_callback request
          # {
          #   "attachment": "{\"id\":\"video/asset/06df2595085111728e1ed31d4aab63b9.mp4\",\"storage\":\"cache\",\"metadata\":{\"size\":5856913,\"mime_type\":\"video/mp4\"}}",
          #   "record": [
          #     "Asset::Video",
          #     "dd7fd925-083c-4869-928d-6d845a2c8cb5"
          #   ],
          #   "name": "asset",
          #   "phase": "store"
          # }
          # promote get, phase: :store, payload: JSON.parse(request.body.read)
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
          r.on String do |identifier|
            r.post 'callback' do
              begin
                opts[:shrine_class].public_send :webhook_callback, identifier, r
              rescue StandardError => e
                opts[:shrine_class].public_send :webhook_callback_failed!, e, identifier, r
              ensure
                response.status = 200
                request.halt
              end
            end
          end
        end
      end
    end

    register_plugin :webhook, Webhook
  end
end
