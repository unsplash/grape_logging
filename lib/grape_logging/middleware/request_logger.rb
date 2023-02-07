require 'grape'
require 'grape/middleware/base'

module GrapeLogging
  module Middleware
    class RequestLogger < Grape::Middleware::Base
      if defined?(ActiveRecord)
        ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          GrapeLogging::Timings.append_db_runtime(event)
        end
      end

      # Persist response status & response (body)
      # to use int in parameters
      attr_accessor :response

      def initialize(app, options = {})
        super

        @included_loggers = @options[:include] || []
        @reporter = if options[:instrumentation_key]
                      Reporters::ActiveSupportReporter.new(@options[:instrumentation_key])
                    else
                      Reporters::LoggerReporter.new(@options[:logger], @options[:formatter], @options[:log_level])
                    end
      end

      def before
        reset_db_runtime
        start_time
        invoke_included_loggers(:before)
      end

      def after(_status, _body, _headers = {})
        stop_time

        # Perform repotters
        @reporter.perform(collect_parameters)

        # Invoke loggers
        invoke_included_loggers(:after)
        nil
      end

      # Call stack and parse responses & status.
      #
      # @note Exceptions are logged as 500 status & re-raised.
      def call!(env)
        @env = env

        # Before hook
        before

        # Catch error
        error = catch(:error) do
          begin
            @app_response = @app.call(@env)
            @response = Rack::Response[*@app_response]
          rescue StandardError => e
            # Log as 500 + message
            status = e.respond_to?(:status) ? e.status : 500
            body = e.message

            after(status, body)

            # Re-raise exception
            raise e
          end
          nil
        end

        # Get status & response from app_response
        # when no error occures.
        if error
          # Call with error & response
          after(error[:status], error[:message])

          # Throw again
          throw(:error, error)
        else
          # Call after hook properly
          after(response.status, response.body, response.headers)
        end

        # Otherwise return original response
        @app_response
      end

      protected

      def parameters
        {
          status: response.status,
          time: {
            total: total_runtime,
            db: db_runtime,
            view: view_runtime
          },
          method: request.request_method,
          path: request.path,
          params: request.params,
          host: request.host
        }
      end

      private

      def request
        @request ||= ::Rack::Request.new(@env)
      end

      def total_runtime
        ((stop_time - start_time) * 1000).round(2)
      end

      def view_runtime
        total_runtime - db_runtime
      end

      def db_runtime
        GrapeLogging::Timings.db_runtime.round(2)
      end

      def reset_db_runtime
        GrapeLogging::Timings.reset_db_runtime
      end

      def start_time
        @start_time ||= Time.now
      end

      def stop_time
        @stop_time ||= Time.now
      end

      def collect_parameters
        parameters.tap do |params|
          @included_loggers.each do |logger|
            params.merge! logger.parameters(request, response) do |_, oldval, newval|
              oldval.respond_to?(:merge) ? oldval.merge(newval) : newval
            end
          end
        end
      end

      def invoke_included_loggers(method_name)
        @included_loggers.each do |logger|
          logger.send(method_name) if logger.respond_to?(method_name)
        end
      end
    end
  end
end
