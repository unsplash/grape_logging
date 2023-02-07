require 'spec_helper'
require 'ostruct'

describe GrapeLogging::Loggers::Response do
  context 'with a parseable JSON body' do
    let(:body) { '{"one": "two", "three": {"four": 5}}' }

    let(:response) do
      Rack::Response.new([body], 200, {})
    end

    it 'returns an array of parseable JSON objects' do
      expect(subject.parameters(nil, response)).to eq({ response: [JSON.parse(body)] })
    end
  end

  context 'with a body that is not parseable JSON' do
    let(:response) do
      Rack::Response.new(['this is a body'], 200, {})
    end

    it 'just returns the body' do
      expect(subject.parameters(nil, response)).to eq({ response: response.body.dup })
    end
  end
end
