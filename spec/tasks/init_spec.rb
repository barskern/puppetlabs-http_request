# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../tasks/init'

describe HTTPRequest do
  let(:url)          { 'http://0.0.0.0:80' }
  let(:success_keys) { %i[body status_code] }

  it 'can make a request' do
    stub_request(:get, "http://0.0.0.0/get")

    opts = {
      method:   'get',
      base_url: "#{url}/get"
    }

    result = subject.task(opts)
    expect(result.keys).to match_array(success_keys)
    expect(result[:status_code]).to eq(200)
  end

  it 'joins the url and path' do
    stub_request(:post, "http://0.0.0.0/post")

    opts = {
      method:   'post',
      base_url: url,
      path:     'post'
    }

    result = subject.task(opts)
    expect(result.keys).to match_array(success_keys)
    expect(result[:status_code]).to eq(200)
  end

  it 'encodes the response body as UTF-8' do
    stub_request(:get, "https://www.google.com/")

    opts = {
      method:   'get',
      base_url: 'https://www.google.com'
    }

    result = subject.task(opts)
    expect(result.keys).to match_array(success_keys)
    expect(result[:body].encoding).to eq(Encoding::UTF_8)
  end

  it 'follows redirects' do
    stub_request(:get, "http://0.0.0.0/redirect-to?url=http://0.0.0.0:80/get").
      to_return({status: 301, headers: {'Location': 'http://0.0.0.0/get'}})

    stub_request(:get, "http://0.0.0.0/get")

    opts = {
      method:           'get',
      base_url:         "#{url}/redirect-to?url=#{url}/get",
      follow_redirects: true,
      max_redirects:    20
    }

    result = subject.task(opts)
    expect(result.keys).to match_array(success_keys)
  end

  it 'errors with too many redirects' do
    for i in 0..5
      stub_request(:get, "http://0.0.0.0/absolute-redirect/#{i}").
        to_return({status: 301, headers: {'Location': "http://0.0.0.0/absolute-redirect/#{i + 1}"}})
    end

    opts = {
      method:           'get',
      base_url:         "#{url}/absolute-redirect/0",
      follow_redirects: true,
      max_redirects:    3
    }

    result = subject.task(opts)
    expect(result.key?(:_error)).to be(true)
  end

  it 'errors if the body is not a String' do
    opts = {
      method:   'post',
      base_url: "#{url}/post",
      body:     { 'foo' => 'bar' }
    }

    result = subject.task(opts)
    expect(result.key?(:_error)).to be(true)
  end

  context 'json_endpoint' do
    let(:opts) do
      {
        method:        'get',
        base_url:      "#{url}/headers",
        json_endpoint: true
      }
    end

     it 'sets the Content-Type header to application/json' do
       stub = stub_request(:get, "http://0.0.0.0/headers").
         to_return({status: 200, body: "{}", headers: {'Content-Type': 'application/json'}})

       _ = subject.task(opts)

       expect(stub).to have_been_requested.once
    end

    it 'allows Content-Type to be overwritten' do
      opts.merge!(headers: { 'Content-Type' => 'text/plain' })

       stub = stub_request(:get, "http://0.0.0.0/headers").
         to_return({status: 200, headers: {'Content-Type': 'text/plain'}})

       _ = subject.task(opts)

       expect(stub).to have_been_requested.once
    end

    it 'formats body as JSON' do
      body = {
        'foo' => 'bar'
      }

      stub = stub_request(:post, "http://0.0.0.0/anything").
         with({body: body, headers: {'Content-Type': 'application/json'}})

      opts = {
        method:        'post',
        base_url:      "#{url}/anything",
        json_endpoint: true,
        body:          body
      }

      _ = subject.task(opts)

      expect(stub).to have_been_requested.once
    end
  end
end
