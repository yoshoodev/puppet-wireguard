# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'base64'

describe 'wireguard::generate_psk' do
  let(:key_directory) { Dir.mktmpdir('wireguard-psks') }
  let(:peer_a) { 'node-a.example.com/wg0' }
  let(:peer_b) { 'node-b.example.com/wg0' }

  after do
    FileUtils.remove_entry(key_directory)
  end

  it 'generates a base64-encoded 32-byte key' do
    key = subject.execute(peer_a, peer_b, key_directory)

    expect(Base64.strict_decode64(key).bytesize).to eq(32)
  end

  it 'reuses the stored key across calls and reversed peer order' do
    key = subject.execute(peer_a, peer_b, key_directory)

    expect(subject.execute(peer_a, peer_b, key_directory)).to eq(key)
    expect(subject.execute(peer_b, peer_a, key_directory)).to eq(key)
    expect(Dir.children(key_directory).length).to eq(1)
  end

  it 'generates different keys for different peer pairs' do
    key = subject.execute(peer_a, peer_b, key_directory)

    expect(subject.execute(peer_a, 'node-c.example.com/wg0', key_directory)).not_to eq(key)
  end

  it 'does not confuse peer identifiers containing separators' do
    key = subject.execute('a:b', 'c', key_directory)

    expect(subject.execute('a', 'b:c', key_directory)).not_to eq(key)
  end

  it 'creates a missing storage directory' do
    directory = File.join(key_directory, 'new', 'psks')
    key = subject.execute(peer_a, peer_b, directory)

    expect(File.read(Dir.glob(File.join(directory, '*.psk')).first)).to eq(key)
  end

  it 'uses the compiler vardir by default' do
    allow(Puppet).to receive(:[]).and_call_original
    allow(Puppet).to receive(:[]).with(:vardir).and_return(key_directory)
    key = subject.execute(peer_a, peer_b)

    expect(subject.execute(peer_b, peer_a, File.join(key_directory, 'wireguard_psks'))).to eq(key)
  end

  it 'returns one shared key to concurrent callers' do
    function = subject
    callers = Array.new(8) do
      Thread.new { function.execute(peer_a, peer_b, key_directory) }
    end

    expect(callers.map(&:value).uniq.length).to eq(1)
    expect(Dir.children(key_directory).length).to eq(1)
  end

  it 'refuses to replace a damaged stored key' do
    subject.execute(peer_a, peer_b, key_directory)
    key_path = Dir.glob(File.join(key_directory, '*.psk')).first
    File.write(key_path, 'damaged-key')

    expect { subject.execute(peer_a, peer_b, key_directory) }.to raise_error(Puppet::Error, %r{stored preshared key is invalid})
    expect(File.read(key_path)).to eq('damaged-key')
  end

  it 'restricts directory and key permissions' do
    subject.execute(peer_a, peer_b, key_directory)
    key_path = Dir.glob(File.join(key_directory, '*.psk')).first

    expect(File.stat(key_directory).mode & 0o777).to eq(0o700)
    expect(File.stat(key_path).mode & 0o777).to eq(0o600)
  end

  it 'rejects relative storage paths' do
    expect { subject.execute(peer_a, peer_b, 'relative/path') }.to raise_error(Puppet::Error, %r{absolute path})
  end
end
