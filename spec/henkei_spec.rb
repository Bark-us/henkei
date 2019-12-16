# frozen_string_literal: true

require 'helper.rb'
require 'henkei'

describe Henkei do
  let(:data) { File.read 'spec/samples/sample.docx' }

  before do
    ENV['JAVA_HOME'] = nil
  end

  describe '.read' do
    it 'reads text' do
      text = Henkei.read :text, data

      expect(text).to include 'The quick brown fox jumped over the lazy cat.'
    end

    it 'reads metadata' do
      metadata = Henkei.read :metadata, data

      expect(metadata['Content-Type']).to(
        eq 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      )
    end

    it 'reads metadata values with colons as strings' do
      data = File.read 'spec/samples/sample-metadata-values-with-colons.doc'
      metadata = Henkei.read :metadata, data

      expect(metadata['dc:title']).to eq 'problem: test'
    end

    it 'reads mimetype' do
      mimetype = Henkei.read :mimetype, data

      expect(mimetype.content_type).to(
        eq 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      )
      expect(mimetype.extensions).to include 'docx'
    end

    it 'closes io on timeout' do
      expect(IO).to receive(:popen).and_wrap_original do |m, *args, &block|
        m.call *args do |io|
          expect(io).to receive(:write).and_wrap_original do |m, *args|
            m.call(*args)
            sleep 0.5
          end
          expect(io).to receive(:close)

          block.call(io)
        end
      end

      expect do
        Henkei.read :html, data, timeout: 0.25
      end.to raise_error Timeout::Error
    end
  end

  describe '.new' do
    it 'requires parameters' do
      expect { Henkei.new }.to raise_error ArgumentError
    end

    it 'accepts a root path' do
      henkei = Henkei.new 'spec/samples/sample.pages'

      expect(henkei).to be_path
      expect(henkei).not_to be_uri
      expect(henkei).not_to be_stream
    end

    it 'accepts a relative path' do
      henkei = Henkei.new 'spec/samples/sample.pages'

      expect(henkei).to be_path
      expect(henkei).not_to be_uri
      expect(henkei).not_to be_stream
    end

    it 'accepts a path with spaces' do
      henkei = Henkei.new 'spec/samples/sample filename with spaces.pages'

      expect(henkei).to be_path
      expect(henkei).not_to be_uri
      expect(henkei).not_to be_stream
    end

    it 'accepts a URI' do
      henkei = Henkei.new 'http://svn.apache.org/repos/asf/poi/trunk/test-data/document/sample.docx'

      expect(henkei).to be_uri
      expect(henkei).not_to be_path
      expect(henkei).not_to be_stream
    end

    it 'accepts a stream or object that can be read' do
      File.open 'spec/samples/sample.pages', 'r' do |file|
        henkei = Henkei.new file

        expect(henkei).to be_stream
        expect(henkei).not_to be_path
        expect(henkei).not_to be_uri
      end
    end

    it 'refuses a path to a missing file' do
      expect { Henkei.new 'test/sample/missing.pages' }.to raise_error Errno::ENOENT
    end

    it 'refuses other objects' do
      [nil, 1, 1.1].each do |object|
        expect { Henkei.new object }.to raise_error TypeError
      end
    end
  end

  describe '.creation_date' do
    let(:henkei) { Henkei.new 'spec/samples/sample.pages' }
    it 'should return Time' do
      expect(henkei.creation_date).to be_a Time
    end
  end

  describe '.java' do
    specify 'with no specified JAVA_HOME' do
      expect(Henkei.send(:java_path)).to eq 'java'
    end

    specify 'with a specified JAVA_HOME' do
      ENV['JAVA_HOME'] = '/path/to/java/home'

      expect(Henkei.send(:java_path)).to eq '/path/to/java/home/bin/java'
    end
  end

  context 'initialized with a given path' do
    let(:henkei) { Henkei.new 'spec/samples/sample.pages' }

    specify '#text reads text' do
      expect(henkei.text).to include 'The quick brown fox jumped over the lazy cat.'
    end

    specify '#metadata reads metadata' do
      expect(henkei.metadata['Content-Type']).to eq %w[application/vnd.apple.pages application/vnd.apple.pages]
    end
  end

  context 'initialized with a given URI' do
    let(:henkei) { Henkei.new 'http://svn.apache.org/repos/asf/poi/trunk/test-data/document/sample.docx' }

    specify '#text reads text' do
      expect(henkei.text).to include 'Lorem ipsum dolor sit amet, consectetuer adipiscing elit.'
    end

    specify '#metadata reads metadata' do
      expect(henkei.metadata['Content-Type']).to(
        eq 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      )
    end
  end

  context 'initialized with a given stream' do
    let(:henkei) { Henkei.new File.open('spec/samples/sample.pages', 'rb') }

    specify '#text reads text' do
      expect(henkei.text).to include 'The quick brown fox jumped over the lazy cat.'
    end

    specify '#metadata reads metadata' do
      expect(henkei.metadata['Content-Type']).to eq %w[application/vnd.apple.pages application/vnd.apple.pages]
    end
  end

  context 'working as server mode' do
    specify '#starts and kills server' do
      begin
        Henkei.server(:text)
        expect(Henkei.class_variable_get(:@@server_pid)).not_to be_nil
        expect(Henkei.class_variable_get(:@@server_port)).not_to be_nil

        s = TCPSocket.new('localhost', Henkei.class_variable_get(:@@server_port))
        expect(s).to be_a TCPSocket
        s.close
      ensure
        port = Henkei.class_variable_get(:@@server_port)
        Henkei.kill_server!
        sleep 2
        expect { TCPSocket.new('localhost', port) }.to raise_error Errno::ECONNREFUSED
      end
    end

    specify '#timesout on long server response' do
      begin
        Henkei.server(:text)

        expect(TCPSocket).to receive(:new).and_wrap_original do |m, *args|
          s = m.call(*args)
          expect(s).to receive(:write).and_wrap_original do |m, *args|
            m.call(*args)
            sleep 5
          end

          s
        end

        expect do
          Henkei.read(:text, data, timeout: 5)
        end.to raise_error Timeout::Error
      ensure
        Henkei.kill_server!
      end
    end

    specify '#runs samples through server mode' do
      begin
        Henkei.server(:text)
        expect(Henkei.new('spec/samples/sample.pages').text).to(
          include 'The quick brown fox jumped over the lazy cat.'
        )
        expect(Henkei.new('spec/samples/sample filename with spaces.pages').text).to(
          include 'The quick brown fox jumped over the lazy cat.'
        )
        expect(Henkei.new('spec/samples/sample.docx').text).to(
          include 'The quick brown fox jumped over the lazy cat.'
        )
      ensure
        Henkei.kill_server!
      end
    end
  end
end
