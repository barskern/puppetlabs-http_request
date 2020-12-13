#!/usr/bin/env ruby
# frozen_string_literal: true

installdir_path = '../../ruby_task_helper/files/task_helper.rb'
local_path = '../files/task_helper.rb'

begin
  # Task is being run with bolt and helper is at location relative to task
  require_relative installdir_path
rescue LoadError
  # Task is being run locally (in a test)
  # TODO: MODULES-8605 reccomend efficient pattern for testing locally
  require_relative local_path
end

require 'json'
require 'net/http'
require 'openssl'

# A task-class which executes HTTP requests based on provided options.
class HTTPRequest < TaskHelper
  def task(**opts)
    # Get all of the request parameters in order...
    method   = opts[:method].capitalize.to_sym
    uri      = URI.parse(opts[:base_url]) + (opts[:path] || '')
    body     = format_body(opts[:body], opts[:json_endpoint])
    headers  = format_headers(opts[:headers], opts[:json_endpoint])
    ssl_opts = {
      cacert: opts[:cacert],
      cert:   opts[:cert],
      key:    opts[:key],
    }

    redirects = 0
    response  = nil

    # Make the request, following redirects if configured to do so.
    # If maximum number of redirects is exceeded, error.
    loop do
      response = request(method, uri, headers, body, ssl_opts)

      break unless response.is_a?(Net::HTTPRedirection) && opts[:follow_redirects]

      if redirects >= opts[:max_redirects]
        raise TaskHelper::Error.new(
          "Too many redirects (max: #{opts[:max_redirects]})",
          'http_request/too-many-redirects-error',
        )
      end

      redirects += 1
      uri = expand_redirect_url(response['location'], opts[:base_url])
    end

    # Return the body and status code of the response.
    {
      body:        parse_response_body(response, opts[:json_endpoint]),
      status_code: response.code.to_i,
    }
  rescue TaskHelper::Error => e
    { _error: e.to_h }
  end

  private

  # Makes the actual request.
  def request(method, uri, headers, body, opts)
    # Create the client
    client = Net::HTTP.new(uri.host, uri.port)

    # Use SSL if requesting a secure connection
    if uri.scheme == 'https'
      client.use_ssl     = true
      client.verify_mode = OpenSSL::SSL::VERIFY_PEER
      client.ca_file     = opts[:cacert] if opts[:cacert]
      client.cert        = OpenSSL::X509::Certificate.new(File.read(opts[:cert])) if opts[:cert]
      client.key         = OpenSSL::PKey::RSA.new(opts[:key]) if opts[:key]
    end

    # Build the request
    request = Net::HTTP.const_get(method).new(uri.request_uri, headers)

    # Build the query if there's data to send
    request.body = body if body

    # Send the request
    client.request(request)
  rescue StandardError => e
    raise TaskHelper::Error.new(
      "Failed to connect to #{uri}: #{e.message}",
      'http_request/connect-error',
    )
  end

  # Parses the response body.
  def parse_response_body(response, json)
    body = encode_body(response.read_body, response.type_params['charset'])

    if json
      begin
        body = JSON.parse(body)
      rescue JSON::ParserError => e
        raise TaskHelper::Error.new(
          "Unable to parse response body as JSON: #{e.message}",
          'http_request/json-parse-error',
        )
      end
    end

    body
  end

  # Forces the response body to the specified encoding and
  # then encodes as UTF-8.
  def encode_body(body, charset)
    body = body.force_encoding(charset) if charset
    body.encode('UTF-8')
  end

  # Formats the body. If the request is a JSON request, this will
  # convert the body to JSON.
  def format_body(body, json)
    if json && !body.is_a?(String) && !body.nil?
      body.to_json
    elsif body.is_a?(String) || body.nil?
      body
    else
      raise TaskHelper::Error.new(
        'body must be a String when json_endpoint is false',
        'http_request/body-type-error',
      )
    end
  end

  # Formats the headers. If the request is a JSON request, this will
  # set the Content-Type header to application/json. This can be
  # overridden by a user.
  def format_headers(headers, json)
    default = json ? { 'Content-Type' => 'application/json' } : {}
    stringify_keys!(default.merge(headers || {}), deep: true)
  end

  # Parses the redirect URL and expands it relative to the
  # base URL if the redirect URL is relative.
  def expand_redirect_url(redirect_url, base_url)
    uri = URI.parse(redirect_url)
    uri = URI.parse(base_url) + redirect_url if uri.relative?
    uri
  end

  def stringify_keys!(arg, options = {})
    case arg
    when Array
      arg.map do |elem|
        (options[:deep]) ? stringify_keys!(elem, options) : elem
      end
    when Hash
      Hash[
        *arg
        .map { |key, value|
           k = key.is_a?(Symbol) ? key.to_s : key
           v = ((options[:deep]) ? stringify_keys!(value, options) : value)
           [k, v]
         }.reduce([]) { |r, x| r + x }]
    else
      arg
    end
  end
end

if $PROGRAM_NAME == __FILE__
  HTTPRequest.run
end
