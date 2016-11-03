=begin
Copyright 2016 Shine Solutions

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
=end

require 'ruby_aem/error'
require 'ruby_aem/handlers/file'
require 'ruby_aem/handlers/html'
require 'ruby_aem/handlers/json'
require 'ruby_aem/handlers/simple'
require 'ruby_aem/handlers/xml'
require 'ruby_aem/response'
require 'ruby_aem/swagger'
require 'swagger_aem'

module RubyAem
  # Client class makes Swagger AEM API calls and handles the response as
  # configured in conf/spec.yaml .
  class Client

    # Initialise a client.
    #
    # @param apis a hash of Swagger AEM client's API instances
    # @param spec ruby_aem specification
    # @return new RubyAem::Client instance
    def initialize(apis, spec)
      @apis = apis
      @spec = spec
    end

    # Make an API call using the relevant Swagger AEM API client.
    # Clazz and action parameters are used to identify the action, API, and params
    # from ruby_aem specification, alongside the response handlers.
    #
    # @param clazz the class name of the caller resource
    # @param action the action of the API call
    # @param info additional information of the API call
    # @return RubyAem::Result
    def call(clazz, action, info)

      resource_name = clazz.name.downcase.sub('rubyaem::resources::', '')
      resource = @spec[resource_name]
      action_spec = resource['actions'][action]

      api = @apis[action_spec['api'].to_sym]
      operation = action_spec['operation']

      params = []
      required_params = action_spec['params']['required'] || {}
      required_params.each { |key, value|
        params.push(value % info)
      }
      params.push({})
      optional_params = action_spec['params']['optional'] || {}
      optional_params.each { |key, value|
        add_optional_param(key, value, params, info)
      }

      base_responses_spec = resource['responses'] || {}
      action_responses_spec = action_spec['responses'] || {}
      responses_spec = base_responses_spec.merge(action_responses_spec)

      begin
        method = RubyAem::Swagger.operation_to_method(operation)
        data, status_code, headers = api.send("#{method}_with_http_info", *params)
        response = RubyAem::Response.new(status_code, data, headers)
      rescue SwaggerAemClient::ApiError => err
        response = RubyAem::Response.new(err.code, err.response_body, err.response_headers)
      end
      handle(response, responses_spec, info)
    end

    # Add optional param into params list.
    #
    # @param key optional param key
    # @param value optional param value
    # @param params combined list of required and optional parameters
    # @param info additional information
    def add_optional_param(key, value, params, info)
      # if there is no value in optional param spec,
      # then only add optional param that is set in info
      if !value
        if info.key? key.to_sym
          params[-1][key.to_sym] = info[key.to_sym]
        end
      # if value is provided in optional param spec,
      # then apply variable interpolation the same way as required param
      else
        if value.class == String
          if value == '__FILE__'
            File.open("#{info[:file_path]}/#{info[:package_name]}-#{info[:package_version]}.zip", 'r') { |file|
              params[-1][key.to_sym] = file
            }
          else
            params[-1][key.to_sym] = value % info
          end
        else
          params[-1][key.to_sym] = value
        end
      end
    end

    # Handle a response based on status code and a given list of response specifications.
    # If none of the response specifications contains the status code, a failure result
    # will then be returned.
    #
    # @param RubyAem::Response response containing HTTP status code, body, and headers
    # @param responses_spec a list of response specifications as configured in conf/spec.yaml
    # @param info additional information
    # @return RubyAem::Result
    # @raise RubyAem::Error when the response status code is unexpected
    def handle(response, responses_spec, info)
      if responses_spec.key?(response.status_code)
        response_spec = responses_spec[response.status_code]
        handler = response_spec['handler']
        result = Handlers.send(handler, response, response_spec, info)
      else
        message = "Unexpected response\nstatus code: #{response.status_code}\nheaders: #{response.headers}\nbody: #{response.body}"
        result = Result.new(message, response)
        raise RubyAem::Error.new(message, result)
      end
    end

  end
end
